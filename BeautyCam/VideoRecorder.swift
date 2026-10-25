import AVFoundation

/// Writes beautified frames + microphone audio to an .mp4. All methods must be called on the camera queue.
final class VideoRecorder {
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var pendingStart = false
    private var sessionStarted = false
    private var audioSettings: [String: Any]?
    private var rotation: CGFloat = 0

    var isRecording: Bool { pendingStart || writer != nil }

    /// Recording actually begins with the next video frame (so we know its size and timestamp).
    func start(audioSettings: [String: Any]?, rotation: CGFloat) {
        guard !isRecording else { return }
        self.audioSettings = audioSettings
        self.rotation = rotation
        pendingStart = true
    }

    /// `buffer` is an already-rendered beautified frame.
    func append(video buffer: CVPixelBuffer, at time: CMTime) {
        if pendingStart {
            setUp(size: CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)), at: time)
        }
        guard sessionStarted, let input = videoInput, input.isReadyForMoreMediaData else { return }
        adaptor?.append(buffer, withPresentationTime: time)
    }

    func append(audio sample: CMSampleBuffer) {
        guard sessionStarted, let input = audioInput, input.isReadyForMoreMediaData else { return }
        input.append(sample)
    }

    func finish(_ completion: @escaping (URL?) -> Void) {
        pendingStart = false
        guard let writer, sessionStarted else {
            reset()
            completion(nil)
            return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        let url = writer.outputURL
        writer.finishWriting { completion(writer.status == .completed ? url : nil) }
        reset()
    }

    private func setUp(size: CGSize, at time: CMTime) {
        pendingStart = false
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BeautyCam-\(UUID().uuidString).mp4")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
        let w = Int(size.width) / 2 * 2, h = Int(size.height) / 2 * 2
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: w * h * 6],
        ])
        video.expectsMediaDataInRealTime = true
        // Track transforms rotate clockwise for positive angles (y-down), Core Image the other way.
        video.transform = CGAffineTransform(rotationAngle: -rotation)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
        ])
        guard writer.canAdd(video) else { return }
        writer.add(video)
        if let audioSettings {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audio.expectsMediaDataInRealTime = true
            if writer.canAdd(audio) {
                writer.add(audio)
                audioInput = audio
            }
        }
        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: time)
        self.writer = writer
        self.videoInput = video
        self.adaptor = adaptor
        sessionStarted = true
    }

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        adaptor = nil
        sessionStarted = false
    }
}
