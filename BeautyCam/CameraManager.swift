import AVFoundation
import QuartzCore
import CoreImage

enum FlashMode: CaseIterable {
    case off, auto, on
    var avMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: .off
        case .auto: .auto
        case .on: .on
        }
    }
}

/// A user-facing camera status message, pre-resolved for the current app language (see `L10n`).
struct CameraStatus: Equatable {
    let message: String
    /// Whether the UI should offer a shortcut to the Settings app (permission denied).
    let needsSettings: Bool
}

/// Snapshot of device capabilities the UI needs. Delivered on the main queue.
struct CameraState {
    var position: AVCaptureDevice.Position = .back
    var zoomButtons: [CGFloat] = [1]       // display factors, e.g. [0.5, 1, 2]
    var minZoom: CGFloat = 1                // display factors
    var maxZoom: CGFloat = 1
    var zoom: CGFloat = 1
    var hasTorch = false
    var flashSupported = false              // AVCapturePhotoOutput can fire a flash (incl. Retina Flash)
    var exposureBiasRange: ClosedRange<Float> = -2...2
}

final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    static var isAvailable: Bool { AVCaptureDevice.default(for: .video) != nil }

    enum SensorFormat { case photo, video }   // 4:3 for stills, 16:9 for recording (like Apple Camera)

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "beautycam.camera")
    private let photoQueue = DispatchQueue(label: "beautycam.photo", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    /// In memory only: kept while the app is alive, back camera on every cold launch.
    private var position: AVCaptureDevice.Position = .back
    private var sensorFormat = SensorFormat.photo
    private var zoomBase: CGFloat = 1   // device zoom factor that corresponds to "1x"
    private var aeafLocked = false
    private var face: FaceInfo?
    private var frameIndex = 0
    private let recorder = VideoRecorder()
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private let framePool = BufferPool()        // full processed frames (preview, recording)
    private let cropPool = BufferPool()         // recorded frames cropped to the chosen aspect
    private var recordAspect: CGFloat?          // width / height of the recording; camera queue only
    private var renderTime: CFTimeInterval = 0
    private var photoCompletions: [Int64: (CIImage?) -> Void] = [:]   // guarded by photoLock
    private let photoLock = NSLock()

    private let lock = NSLock()
    private var _params = BeautyParams()
    var params: BeautyParams {
        get { lock.withLock { _params } }
        set { lock.withLock { _params = newValue } }
    }

    /// Called on the camera queue with each processed frame.
    var onFrame: ((CIImage) -> Void)?
    /// Called with a user-facing status when the camera cannot start (nil once frames flow).
    var onStatus: ((CameraStatus?) -> Void)?
    /// Device capabilities changed (camera switched, format changed). Main queue.
    var onState: ((CameraState) -> Void)?
    /// The focus point was reset by the system (subject area changed). Main queue.
    var onFocusReset: (() -> Void)?
    /// The shutter fired (for the capture animation). Main queue.
    var onWillCapture: (() -> Void)?
    private var deliveredFirstFrame = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaChanged),
                                               name: AVCaptureDevice.subjectAreaDidChangeNotification, object: nil)
    }

    // MARK: - Session lifecycle

    /// Safe to call repeatedly (e.g. every time the app becomes active).
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { self.run() }
        case .notDetermined:
            print("[BeautyCam] requesting camera access")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("[BeautyCam] camera access granted=\(granted)")
                if granted {
                    self.queue.async { self.run() }
                } else {
                    self.onStatus?(CameraStatus(message: L10n.t("没有相机权限，请在 设置 > Arinoa美颜 中打开相机"), needsSettings: true))
                }
            }
        default:
            print("[BeautyCam] camera access denied/restricted")
            onStatus?(CameraStatus(message: L10n.t("没有相机权限，请在 设置 > Arinoa美颜 中打开相机"), needsSettings: true))
        }
    }

    private func run() {
        if videoInput == nil { configure() }
        guard !session.isRunning else { return }
        session.startRunning()
        print("[BeautyCam] session running=\(session.isRunning) inputs=\(session.inputs.count) outputs=\(session.outputs.count)")
        if !session.isRunning { onStatus?(CameraStatus(message: L10n.t("相机启动失败"), needsSettings: false)) }
    }

    func stop() { queue.async { self.session.stopRunning() } }

    func switchCamera() {
        queue.async {
            self.position = self.position == .front ? .back : .front
            self.face = nil
            self.configure()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func setSensorFormat(_ format: SensorFormat) {
        queue.async {
            guard format != self.sensorFormat else { return }
            self.sensorFormat = format
            guard let device = self.videoInput?.device else { return }
            self.session.beginConfiguration()
            self.applyFormat(to: device)
            self.session.commitConfiguration()
            self.publishState()
        }
    }

    /// Microphone is attached only in video mode, so photo mode never interrupts other audio.
    func setAudioEnabled(_ enabled: Bool) {
        let attach = {
            self.queue.async {
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }
                if enabled, self.audioInput == nil,
                   let mic = AVCaptureDevice.default(for: .audio),
                   let input = try? AVCaptureDeviceInput(device: mic), self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.audioInput = input
                    if !self.session.outputs.contains(self.audioOutput), self.session.canAddOutput(self.audioOutput) {
                        self.audioOutput.setSampleBufferDelegate(self, queue: self.queue)
                        self.session.addOutput(self.audioOutput)
                    }
                } else if !enabled, let input = self.audioInput {
                    self.session.removeInput(input)
                    self.audioInput = nil
                }
            }
        }
        if enabled { AVCaptureDevice.requestAccess(for: .audio) { _ in attach() } } else { attach() }
    }

    // MARK: - Configuration

    private func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Virtual multi-camera devices switch lenses automatically as zoom changes (0.5x → ultra wide).
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position).devices
        for type in types { if let d = found.first(where: { $0.deviceType == type }) { return d } }
        return nil
    }

    private func configure() {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
            publishState()
        }
        session.sessionPreset = .inputPriority
        if let old = videoInput { session.removeInput(old) }
        videoInput = nil
        guard let device = bestDevice(for: position) else {
            print("[BeautyCam] no camera device for position \(position.rawValue)")
            onStatus?(CameraStatus(message: L10n.t("找不到摄像头"), needsSettings: false))
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                print("[BeautyCam] cannot add camera input")
                onStatus?(CameraStatus(message: L10n.t("无法使用摄像头"), needsSettings: false))
                return
            }
            session.addInput(input)
            videoInput = input
        } catch {
            print("[BeautyCam] camera input error: \(error)")
            onStatus?(CameraStatus(message: L10n.t("无法打开摄像头"), needsSettings: false))
            return
        }

        if !session.outputs.contains(videoOutput) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        }
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        for conn in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)].compactMap({ $0 }) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = position == .front
        }

        applyFormat(to: device)

        // "1x" is the wide lens. On virtual devices with an ultra wide, that is the first switch-over factor.
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        zoomBase = hasUltraWide ? CGFloat(truncating: device.virtualDeviceSwitchOverVideoZoomFactors.first ?? 1) : 1
        aeafLocked = false
        try? device.lockForConfiguration()
        device.videoZoomFactor = zoomBase
        device.isSubjectAreaChangeMonitoringEnabled = true
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()
    }

    /// Picks a 30fps format with the wanted aspect (4:3 photo / 16:9 video), ≤1920 wide for real-time
    /// beauty, preferring the largest still-photo resolution.
    private func applyFormat(to device: AVCaptureDevice) {
        let ratio: Double = sensorFormat == .photo ? 4.0 / 3.0 : 16.0 / 9.0
        func dims(_ f: AVCaptureDevice.Format) -> CMVideoDimensions { CMVideoFormatDescriptionGetDimensions(f.formatDescription) }
        func photoPixels(_ f: AVCaptureDevice.Format) -> Int32 {
            f.supportedMaxPhotoDimensions.map { $0.width * $0.height }.max() ?? 0
        }
        let candidates = device.formats.filter { f in
            let d = dims(f)
            return abs(Double(d.width) / Double(d.height) - ratio) < 0.02 && d.width <= 1920 && d.width >= 1280
                && f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
                && CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }
        guard let best = candidates.max(by: { (dims($0).width, photoPixels($0)) < (dims($1).width, photoPixels($1)) }) else {
            print("[BeautyCam] no matching format, falling back to preset")
            session.sessionPreset = sensorFormat == .photo ? .photo : .hd1920x1080
            return
        }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        } catch {
            print("[BeautyCam] format lock failed: \(error)")
        }
        if let maxDims = best.supportedMaxPhotoDimensions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            photoOutput.maxPhotoDimensions = maxDims
        }
        print("[BeautyCam] format \(dims(best).width)x\(dims(best).height) photo \(photoOutput.maxPhotoDimensions.width)x\(photoOutput.maxPhotoDimensions.height)")
    }

    private func publishState() {
        guard let device = videoInput?.device else { return }
        var s = CameraState()
        s.position = position
        let base = zoomBase
        s.minZoom = device.minAvailableVideoZoomFactor / base
        s.maxZoom = min(device.maxAvailableVideoZoomFactor, base * 10) / base
        s.zoom = device.videoZoomFactor / base
        var buttons: [CGFloat] = []
        if base > 1 { buttons.append(0.5) }
        buttons.append(1)
        let teles = device.virtualDeviceSwitchOverVideoZoomFactors.dropFirst(base > 1 ? 1 : 0)
            .map { CGFloat(truncating: $0) / base }
        buttons.append(contentsOf: teles.isEmpty && position == .back ? [2] : teles)
        s.zoomButtons = position == .back ? buttons : [1]
        s.hasTorch = device.hasTorch
        s.flashSupported = photoOutput.supportedFlashModes.contains(.on)
        s.exposureBiasRange = max(device.minExposureTargetBias, -2)...min(device.maxExposureTargetBias, 2)
        DispatchQueue.main.async { self.onState?(s) }
    }

    // MARK: - Focus, exposure, zoom, torch

    /// `point` is in device coordinates (0...1, landscape sensor space).
    func focus(at point: CGPoint, lockAEAF: Bool) {
        queue.async {
            guard let device = self.videoInput?.device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
            if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
            device.setExposureTargetBias(0)
            if lockAEAF {
                if device.isExposureModeSupported(.autoExpose) { device.exposureMode = .autoExpose }
                device.isSubjectAreaChangeMonitoringEnabled = false
                self.aeafLocked = true
                // Let AF/AE settle on the point, then freeze both.
                self.queue.asyncAfter(deadline: .now() + 0.6) {
                    guard self.aeafLocked, (try? device.lockForConfiguration()) != nil else { return }
                    if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                    if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                    device.unlockForConfiguration()
                }
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.isSubjectAreaChangeMonitoringEnabled = true
                self.aeafLocked = false
            }
        }
    }

    /// Freezes focus and exposure where they are now (tap-to-shoot mode), or returns to continuous auto.
    func setAEAFLocked(_ locked: Bool) {
        queue.async {
            guard let device = self.videoInput?.device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            self.aeafLocked = locked
            device.isSubjectAreaChangeMonitoringEnabled = !locked
            if locked {
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            } else {
                let center = CGPoint(x: 0.5, y: 0.5)
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = center }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = center }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.setExposureTargetBias(0)
            }
        }
    }

    func setExposureBias(_ bias: Float) {
        queue.async {
            guard let device = self.videoInput?.device, (try? device.lockForConfiguration()) != nil else { return }
            device.setExposureTargetBias(max(device.minExposureTargetBias, min(device.maxExposureTargetBias, bias)))
            device.unlockForConfiguration()
        }
    }

    /// `factor` is a display factor (1 = wide lens).
    func setZoom(_ factor: CGFloat, animated: Bool = false) {
        queue.async {
            guard let device = self.videoInput?.device, (try? device.lockForConfiguration()) != nil else { return }
            let f = max(device.minAvailableVideoZoomFactor,
                        min(factor * self.zoomBase, device.maxAvailableVideoZoomFactor, self.zoomBase * 10))
            if animated { device.ramp(toVideoZoomFactor: f, withRate: 8) } else { device.videoZoomFactor = f }
            device.unlockForConfiguration()
        }
    }

    func setTorch(_ on: Bool) {
        queue.async {
            guard let device = self.videoInput?.device, device.hasTorch,
                  (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    @objc private func subjectAreaChanged(_ note: Notification) {
        queue.async {
            guard !self.aeafLocked, let device = self.videoInput?.device,
                  (try? device.lockForConfiguration()) != nil else { return }
            let center = CGPoint(x: 0.5, y: 0.5)
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = center }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = center }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.setExposureTargetBias(0)
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.onFocusReset?() }
        }
    }

    // MARK: - Photo

    /// Captures a full-resolution still, then applies the current beauty settings to it.
    /// The completion receives the processed, upright image (or nil) on the photo queue.
    func capturePhoto(flash: FlashMode, completion: @escaping (CIImage?) -> Void) {
        queue.async {
            let settings = AVCapturePhotoSettings()
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            settings.photoQualityPrioritization = .balanced
            if self.photoOutput.supportedFlashModes.contains(flash.avMode) { settings.flashMode = flash.avMode }
            self.photoLock.withLock { self.photoCompletions[settings.uniqueID] = completion }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        DispatchQueue.main.async { self.onWillCapture?() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let completion = photoLock.withLock { photoCompletions.removeValue(forKey: photo.resolvedSettings.uniqueID) }
        guard let completion else { return }
        guard error == nil, let data = photo.fileDataRepresentation(),
              let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            print("[BeautyCam] photo failed: \(String(describing: error))")
            completion(nil)
            return
        }
        let p = params
        photoQueue.async {
            let upright = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            let face = FaceDetector.detect(in: upright)
            print("[BeautyCam] photo \(upright.extent.size) face=\(face != nil)")
            completion(BeautyEngine.shared.process(upright, face: face, params: p))
        }
    }

    // MARK: - Video

    /// `aspect` is width / height of the recorded video; frames are center-cropped to it.
    /// `rotation` (radians, counter-clockwise) is stored in the file so players show it upright.
    func startRecording(aspect: CGFloat, rotation: CGFloat) {
        queue.async {
            self.recordAspect = aspect
            let settings = self.audioInput == nil ? nil
                : self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4)
            self.recorder.start(audioSettings: settings, rotation: rotation)
        }
    }

    func stopRecording(_ completion: @escaping (URL?) -> Void) {
        queue.async { self.recorder.finish(completion) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === audioOutput {
            recorder.append(audio: sampleBuffer)
            return
        }
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pb)
        let p = params

        // Landmarks every other frame is plenty; smooth them to avoid jitter.
        frameIndex += 1
        if !p.bypass, p.eyes > 0.01 || p.slim > 0.01 || p.smooth > 0.01 || p.whiten > 0.01, frameIndex % 2 == 0 {
            if let detected = FaceDetector.detect(in: image) {
                face = face.map { $0.blended(toward: detected, 0.5) } ?? detected
            } else {
                face = nil
            }
        }
        let processed = BeautyEngine.shared.process(image, face: face, params: p)

        // Render the finished frame synchronously into a buffer we own. The camera recycles `pb`
        // as soon as this callback returns, so drawing the lazy CIImage later (at display time)
        // reads a half-overwritten buffer and tears the picture.
        let start = CACurrentMediaTime()
        guard let out = framePool.buffer(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb)) else { return }
        BeautyEngine.shared.context.render(processed, to: out, bounds: image.extent, colorSpace: srgb)
        renderTime += CACurrentMediaTime() - start
        if frameIndex % 90 == 0 {
            print(String(format: "[BeautyCam] avg render %.1f ms", renderTime / 90 * 1000))
            renderTime = 0
        }

        if !deliveredFirstFrame {
            deliveredFirstFrame = true
            print("[BeautyCam] first frame \(image.extent)")
            onStatus?(nil)
        }
        if recorder.isRecording {
            recorder.append(video: recordedFrame(out, extent: image.extent),
                            at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        onFrame?(CIImage(cvPixelBuffer: out, options: [.colorSpace: srgb]))
    }

    /// Center-crops a processed frame to the recording aspect (or returns it as is when it matches).
    private func recordedFrame(_ frame: CVPixelBuffer, extent: CGRect) -> CVPixelBuffer {
        guard let aspect = recordAspect else { return frame }
        var w = extent.width, h = extent.height
        if w / h > aspect + 0.01 { w = h * aspect } else if w / h < aspect - 0.01 { h = w / aspect } else { return frame }
        let width = Int(w) / 2 * 2, height = Int(h) / 2 * 2   // encoders want even sizes
        let crop = CGRect(x: (extent.width - CGFloat(width)) / 2, y: (extent.height - CGFloat(height)) / 2,
                          width: CGFloat(width), height: CGFloat(height))
        guard let out = cropPool.buffer(width: width, height: height) else { return frame }
        let image = CIImage(cvPixelBuffer: frame, options: [.colorSpace: srgb])
            .cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        BeautyEngine.shared.context.render(image, to: out, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                                           colorSpace: srgb)
        return out
    }
}

/// BGRA, Metal-compatible pixel buffers of one size. Buffers stay out of the pool while the preview
/// or recorder still holds them. Camera queue only.
final class BufferPool {
    private var pool: CVPixelBufferPool?
    private var width = 0, height = 0

    func buffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil || width != self.width || height != self.height {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            pool = nil
            CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey as String: 4] as CFDictionary,
                                    attrs as CFDictionary, &pool)
            self.width = width
            self.height = height
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
