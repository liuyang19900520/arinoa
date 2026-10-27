import Photos
import PhotosUI
import SwiftUI

@main
struct BeautyCamApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, (AppLanguage(rawValue: languageRaw) ?? .system).locale)
        }
    }
}

enum AspectRatio: String, CaseIterable {
    case r3x4 = "3:4", r9x16 = "9:16", r1x1 = "1:1"
    var widthOverHeight: CGFloat {
        switch self {
        case .r3x4: 3.0 / 4.0
        case .r9x16: 9.0 / 16.0
        case .r1x1: 1
        }
    }
}

struct FocusMark: Equatable {
    var point: CGPoint      // in preview view coordinates
    var locked: Bool
    var id = UUID()
}

@MainActor
final class BeautyViewModel: ObservableObject {
    @Published var params = BeautyParams() { didSet { apply() } }
    @Published var photoMode = !CameraManager.isAvailable   // editing an imported photo
    @Published var toast: String?
    @Published var captureMode = CaptureMode.photo { didSet { captureModeChanged() } }
    @Published var recordingSince: Date?
    /// Shown over the preview until the first camera frame arrives.
    @Published var cameraStatus: CameraStatus? = CameraStatus(message: L10n.t("正在打开相机…"), needsSettings: false)

    // Camera controls
    @Published var cameraState = CameraState()
    // Each mode remembers its own aspect, with Apple Camera's defaults.
    @Published var photoAspect = AspectRatio.r3x4
    @Published var videoAspect = AspectRatio.r9x16 { didSet { updateSensorFormat() } }
    var aspect: AspectRatio {
        get { captureMode == .video ? videoAspect : photoAspect }
        set { if captureMode == .video { videoAspect = newValue } else { photoAspect = newValue } }
    }
    @Published var flash = FlashMode.off
    @Published var torchOn = false
    @Published var timerSeconds = 0          // 0 / 3 / 10
    @Published var grid = false
    @Published var countdown: Int?
    @Published var zoom: CGFloat = 1
    @Published var focusMark: FocusMark?
    @Published var exposureBias: Float = 0
    @Published var shutterBlink = false
    @Published var screenFlash = false
    @Published var lastThumbnail: UIImage?
    @Published var isCapturing = false
    /// 轻点拍照: tapping the preview shoots (and snaps stills while recording); focus/exposure stay locked.
    @Published var tapToShoot = false { didSet { tapToShootChanged() } }

    enum CaptureMode: String, CaseIterable { case photo = "拍照", video = "视频" }

    let renderer = PreviewRenderer()
    private let camera = CameraManager()
    private let orientation = OrientationMonitor()
    private var photo: CIImage?
    private var photoFace: FaceInfo?
    private var countdownTask: Task<Void, Never>?
    private var savedBrightness: CGFloat?

    /// Aspect of the live preview / output. Video is always 9:16 like Apple Camera.
    var previewAspect: CGFloat { aspect.widthOverHeight }
    /// The sensor format: photos always use 4:3 (full resolution); video uses 16:9 for 9:16 and
    /// 4:3 for 3:4 / 1:1 (cropped), which keeps the widest field of view.
    private var sensorFormat: CameraManager.SensorFormat {
        captureMode == .video && videoAspect == .r9x16 ? .video : .photo
    }
    /// Aspect of the frames the sensor delivers (portrait).
    private var frameAspect: CGFloat { sensorFormat == .video ? 9.0 / 16.0 : 3.0 / 4.0 }

    init() {
        camera.onFrame = { [weak self] image in self?.renderer.image = image }
        camera.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.cameraStatus = status
                // The first frame just showed up: the live path is warm, so use the spare cycles to
                // precompute the other filter LUTs instead of making the user wait the first time
                // they pick one.
                if status == nil { BeautyEngine.shared.prewarmStyles() }
            }
        }
        camera.onState = { [weak self] state in
            guard let self else { return }
            self.cameraState = state
            self.zoom = state.zoom
            self.focusMark = nil
            self.exposureBias = 0
            if !state.hasTorch { self.torchOn = false }
            // A camera switch resets focus/exposure; re-lock once auto exposure has settled.
            if self.tapToShoot {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    if self.tapToShoot { self.camera.setAEAFLocked(true) }
                }
            }
        }
        camera.onFocusReset = { [weak self] in
            if self?.focusMark?.locked == false { self?.focusMark = nil }
            self?.exposureBias = 0
        }
        camera.onWillCapture = { [weak self] in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.shutterBlink = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                self?.shutterBlink = false
                self?.endScreenFlash()
            }
        }
        renderer.fill = !photoMode
        orientation.start()
        // Load the CIKernels / CIContext off the main thread, concurrently with the camera queue's
        // own start-up, so the first camera frame doesn't stall on cold kernel loading.
        Task.detached(priority: .utility) { _ = BeautyEngine.shared }
    }

    /// Rotation that makes what the camera captures right now upright (phone held landscape etc.).
    private var uprightRotation: CGFloat { orientation.uprightRotation(frontCamera: cameraState.position == .front) }

    /// Called whenever the app becomes active, so a permission granted later (or a launch
    /// that happened while the phone was locked) still ends up with a running camera.
    func appBecameActive() {
        if !photoMode { camera.start() }
    }

    private func apply() {
        if photoMode, let photo {
            renderer.image = BeautyEngine.shared.process(photo, face: photoFace, params: params)
        } else {
            camera.params = params
        }
    }

    private func captureModeChanged() {
        camera.setAudioEnabled(captureMode == .video)
        updateSensorFormat()
        if captureMode == .photo, torchOn {
            torchOn = false
            camera.setTorch(false)
        }
    }

    private func updateSensorFormat() { camera.setSensorFormat(sensorFormat) }

    // MARK: - Imported photo editing

    func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else { return }
        await load(ui)
    }

    /// Debug: `-demoImage /path/to/face.jpg` launch argument loads a photo directly.
    func loadDemoIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoImage"), i + 1 < args.count,
              let ui = UIImage(contentsOfFile: args[i + 1]) else { return }
        await load(ui)
    }

    func load(_ ui: UIImage) async {
        // Normalize orientation and cap resolution.
        let scale = min(1, 2048 / max(ui.size.width, ui.size.height))
        let size = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
        let normalized = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
        guard let ci = CIImage(image: normalized) else { return }
        let face = await Task.detached { FaceDetector.detect(in: ci) }.value
        photo = ci
        photoFace = face
        photoMode = true
        renderer.fill = false
        camera.stop()
        toast = face == nil ? L10n.t("未检测到人脸：美颜不生效") : L10n.t("已检测到人脸")
        apply()
    }

    func backToCamera() {
        guard CameraManager.isAvailable else { return }
        photoMode = false
        photo = nil
        renderer.fill = true
        cameraStatus = CameraStatus(message: L10n.t("正在打开相机…"), needsSettings: false)
        camera.start()
        apply()
    }

    // MARK: - Beauty / filter

    /// Filters only change color; they never touch the beauty settings.
    func selectStyle(_ style: StylePreset) {
        params.style = style.id
        params.styleIntensity = style.defaultIntensity
    }

    func selectBeautyPreset(_ preset: BeautyPreset) { preset.apply(to: &params) }

    // MARK: - Camera controls

    func switchCamera() {
        torchOn = false
        camera.switchCamera()
    }

    /// Tap (or long-press to lock) at a point of the preview view, whose size is `size`.
    func focus(at point: CGPoint, in size: CGSize, lock: Bool) {
        guard !photoMode, size.width > 0, size.height > 0 else { return }
        // The preview aspect-fills the frame; map the tap back to normalized image coordinates.
        let viewAspect = size.width / size.height
        var u: CGFloat, v: CGFloat
        if frameAspect > viewAspect {
            let dispW = size.height * frameAspect
            u = (point.x + (dispW - size.width) / 2) / dispW
            v = point.y / size.height
        } else {
            let dispH = size.width / frameAspect
            u = point.x / size.width
            v = (point.y + (dispH - size.height) / 2) / dispH
        }
        u = min(max(u, 0), 1); v = min(max(v, 0), 1)
        // Portrait frames are the landscape sensor rotated 90°; the front camera is also mirrored.
        let devicePoint = cameraState.position == .front ? CGPoint(x: v, y: u) : CGPoint(x: v, y: 1 - u)
        camera.focus(at: devicePoint, lockAEAF: lock)
        focusMark = FocusMark(point: point, locked: lock)
        exposureBias = 0
        if lock { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    private func tapToShootChanged() {
        camera.setAEAFLocked(tapToShoot)
        focusMark = nil
        if !tapToShoot { exposureBias = 0 }
        toast = tapToShoot ? L10n.t("轻点屏幕拍照（对焦/曝光已锁定）") : L10n.t("已恢复点击对焦")
    }

    /// A plain tap on the preview: shoots in tap-to-shoot mode, otherwise focuses there.
    func previewTapped(at point: CGPoint, in size: CGSize) {
        guard tapToShoot, !photoMode else {
            focus(at: point, in: size, lock: false)
            return
        }
        if captureMode == .photo {
            shutter()
        } else if recordingSince != nil {
            photoWhileRecording()
        }
    }

    func setExposureBias(_ bias: Float) {
        let r = cameraState.exposureBiasRange
        exposureBias = min(max(bias, r.lowerBound), r.upperBound)
        camera.setExposureBias(exposureBias)
    }

    func setZoom(_ factor: CGFloat, animated: Bool = false) {
        zoom = min(max(factor, cameraState.minZoom), cameraState.maxZoom)
        camera.setZoom(zoom, animated: animated)
    }

    func cycleFlash() {
        if captureMode == .video {
            guard cameraState.hasTorch else {
                toast = L10n.t("前置摄像头不支持补光灯")
                return
            }
            torchOn.toggle()
            camera.setTorch(torchOn)
        } else {
            let all = FlashMode.allCases
            flash = all[(all.firstIndex(of: flash)! + 1) % all.count]
        }
    }

    func cycleTimer() { timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0) }

    func cycleAspect() {
        let all = AspectRatio.allCases
        aspect = all[(all.firstIndex(of: aspect)! + 1) % all.count]
    }

    // MARK: - Shutter

    func shutter() {
        if photoMode { saveImportedPhoto(); return }
        if countdown != nil {   // tapping during the countdown cancels it
            countdownTask?.cancel()
            countdown = nil
            return
        }
        if captureMode == .video, recordingSince != nil {
            stopRecording()
            return
        }
        guard timerSeconds > 0 else { fire(); return }
        countdownTask = Task {
            for n in stride(from: timerSeconds, to: 0, by: -1) {
                countdown = n
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            countdown = nil
            fire()
        }
    }

    private func fire() {
        if captureMode == .video {
            camera.startRecording(aspect: videoAspect.widthOverHeight, rotation: uprightRotation)
            recordingSince = Date()
        } else {
            takePhoto()
        }
    }

    /// Saves a full-resolution still at the video's aspect without interrupting the recording (no flash).
    func photoWhileRecording() {
        guard recordingSince != nil else { return }
        takePhoto(flash: .off, aspect: videoAspect)
    }

    private func takePhoto() { takePhoto(flash: flash, aspect: aspect) }

    private func takePhoto(flash mode: FlashMode, aspect: AspectRatio) {
        guard !isCapturing else { return }
        isCapturing = true
        // Front cameras without Retina Flash: light the face with a white, full-brightness screen.
        let needsScreenFlash = cameraState.position == .front && !cameraState.flashSupported && mode == .on
        let rotation = uprightRotation
        Task {
            if needsScreenFlash {
                screenFlash = true
                savedBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = 1
                try? await Task.sleep(for: .milliseconds(300))
            }
            camera.capturePhoto(flash: mode) { [weak self] image in
                guard let self else { return }
                let result = image.flatMap { Self.encode($0, aspect: aspect, rotation: rotation) }
                Task { @MainActor in
                    self.isCapturing = false
                    self.endScreenFlash()
                    guard let (data, thumb) = result else {
                        self.toast = L10n.t("拍照失败")
                        return
                    }
                    self.lastThumbnail = thumb
                    self.savePhotoData(data)
                }
            }
        }
    }

    private func endScreenFlash() {
        guard screenFlash else { return }
        screenFlash = false
        if let b = savedBrightness { UIScreen.main.brightness = b }
        savedBrightness = nil
    }

    /// Rotates the portrait capture upright by `rotation` (radians, counter-clockwise), center-crops
    /// it to `aspect` (nil keeps it as is; flipped for landscape, so 3:4 becomes 4:3) and encodes it
    /// as JPEG, plus a small thumbnail.
    nonisolated private static func encode(_ image: CIImage, aspect: AspectRatio?, rotation: CGFloat = 0) -> (Data, UIImage)? {
        var image = image
        if rotation != 0 {
            image = image.transformed(by: CGAffineTransform(rotationAngle: rotation))
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        }
        let landscape = abs(abs(rotation) - .pi / 2) < 0.01
        let e = image.extent
        var crop = e
        if let a = aspect?.widthOverHeight {
            let target = landscape ? 1 / a : a
            if e.width / e.height > target {
                let w = (e.height * target).rounded()
                crop = CGRect(x: e.minX + (e.width - w) / 2, y: e.minY, width: w, height: e.height)
            } else if e.width / e.height < target {
                let h = (e.width / target).rounded()
                crop = CGRect(x: e.minX, y: e.minY + (e.height - h) / 2, width: e.width, height: h)
            }
        }
        let cropped = image.cropped(to: crop)
        let ctx = BeautyEngine.shared.context
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3)!
        guard let data = ctx.jpegRepresentation(of: cropped, colorSpace: space,
                                                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.92])
        else { return nil }
        let s = 160 / max(crop.width, crop.height)
        let small = cropped.transformed(by: CGAffineTransform(scaleX: s, y: s))
        guard let cg = ctx.createCGImage(small, from: small.extent) else { return nil }
        return (data, UIImage(cgImage: cg))
    }

    /// `done` runs once the video is saved (or failed); used to end the background task.
    private func stopRecording(done: (() -> Void)? = nil) {
        recordingSince = nil
        camera.stopRecording { url in
            guard let url else {
                Task { @MainActor in self.toast = L10n.t("录制失败") }
                done?()
                return
            }
            self.saveVideo(url, done: done)
        }
    }

    /// Leaving the app (closing the page, swiping home or to another app) ends a recording and
    /// saves it, like Apple Camera. A background task keeps the app alive while the file is written.
    func appEnteredBackground() {
        countdownTask?.cancel()
        countdown = nil
        guard recordingSince != nil else { return }
        let app = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = app.beginBackgroundTask(withName: "finish-recording") { app.endBackgroundTask(task) }
        stopRecording { DispatchQueue.main.async { app.endBackgroundTask(task) } }
    }

    // MARK: - Saving

    nonisolated private func withAddPermission(_ action: @escaping () -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.toast = L10n.t("没有相册权限") }
                return
            }
            action()
        }
    }

    nonisolated private func savePhotoData(_ data: Data) {
        withAddPermission {
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            } completionHandler: { ok, _ in
                if !ok { Task { @MainActor in self.toast = L10n.t("保存失败") } }
            }
        }
    }

    nonisolated private func saveVideo(_ url: URL, done: (() -> Void)? = nil) {
        withAddPermission {
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { ok, _ in
                try? FileManager.default.removeItem(at: url)
                Task { @MainActor in self.toast = ok ? L10n.t("视频已保存到相册") : L10n.t("保存失败") }
                done?()
            }
        }
    }

    private func saveImportedPhoto() {
        guard let photo,
              let (data, thumb) = Self.encode(BeautyEngine.shared.process(photo, face: photoFace, params: params), aspect: nil)
        else { return }
        lastThumbnail = thumb
        savePhotoData(data)
        toast = L10n.t("已保存到相册")
    }
}
