import CoreImage
import Vision

/// Slider values are 0...1. 1 means "strong but still human"; the mapping to raw algorithm
/// strengths lives in BeautyEngine.process.
struct BeautyParams {
    // Defaults = 「自然」. A camera must look real first; beauty is a light touch on top.
    var smooth: Float = 0.3   // 磨皮
    var whiten: Float = 0.1   // 美白
    var eyes: Float = 0.1     // 大眼
    var slim: Float = 0.1     // 瘦脸
    var style = 0             // StylePreset.all index
    var styleIntensity: Float = 0.8
    var bypass = false        // 按住对比原图
}

/// One-tap beauty looks. Starting points to tune from real-device testing.
struct BeautyPreset: Identifiable {
    let id: Int
    let name: String
    let smooth: Float, whiten: Float, eyes: Float, slim: Float

    static let all = [
        BeautyPreset(id: 0, name: "原生", smooth: 0, whiten: 0, eyes: 0, slim: 0),
        BeautyPreset(id: 1, name: "自然", smooth: 0.3, whiten: 0.1, eyes: 0.1, slim: 0.1),
        BeautyPreset(id: 2, name: "精致", smooth: 0.5, whiten: 0.25, eyes: 0.25, slim: 0.25),
        BeautyPreset(id: 3, name: "网红", smooth: 0.7, whiten: 0.4, eyes: 0.45, slim: 0.45),
    ]

    func apply(to p: inout BeautyParams) {
        p.smooth = smooth; p.whiten = whiten; p.eyes = eyes; p.slim = slim
    }

    func matches(_ p: BeautyParams) -> Bool {
        abs(p.smooth - smooth) < 0.005 && abs(p.whiten - whiten) < 0.005
            && abs(p.eyes - eyes) < 0.005 && abs(p.slim - slim) < 0.005
    }
}

/// Key face geometry in Core Image pixel coordinates (origin bottom-left).
struct FaceInfo {
    var leftEye: CGPoint
    var rightEye: CGPoint
    var eyeRadius: CGFloat
    var leftJaw: CGPoint
    var rightJaw: CGPoint
    var anchor: CGPoint          // where the jaw is pulled toward (between nose and chin)
    var faceWidth: CGFloat
    var faceCenter: CGPoint      // face ellipse (incl. forehead) for skin retouching
    var faceAxes: CGSize
    var roll: CGFloat            // radians, eye line angle

    /// Exponential smoothing to reduce landmark jitter between video frames.
    func blended(toward n: FaceInfo, _ a: CGFloat) -> FaceInfo {
        func l(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: p.x + (q.x - p.x) * a, y: p.y + (q.y - p.y) * a) }
        func l(_ p: CGFloat, _ q: CGFloat) -> CGFloat { p + (q - p) * a }
        return FaceInfo(leftEye: l(leftEye, n.leftEye), rightEye: l(rightEye, n.rightEye),
                        eyeRadius: l(eyeRadius, n.eyeRadius),
                        leftJaw: l(leftJaw, n.leftJaw), rightJaw: l(rightJaw, n.rightJaw),
                        anchor: l(anchor, n.anchor), faceWidth: l(faceWidth, n.faceWidth),
                        faceCenter: l(faceCenter, n.faceCenter),
                        faceAxes: CGSize(width: l(faceAxes.width, n.faceAxes.width),
                                         height: l(faceAxes.height, n.faceAxes.height)),
                        roll: l(roll, n.roll))
    }
}

enum FaceDetector {
    /// Detects the largest face and extracts the geometry the kernels need.
    static func detect(in image: CIImage) -> FaceInfo? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try? handler.perform([request])
        guard let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              let lm = face.landmarks,
              let leftEye = lm.leftEye, let rightEye = lm.rightEye,
              let contour = lm.faceContour, let nose = lm.nose else { return nil }

        let size = image.extent.size
        let origin = image.extent.origin
        func pts(_ r: VNFaceLandmarkRegion2D) -> [CGPoint] {
            r.pointsInImage(imageSize: size).map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
        }
        func center(_ p: [CGPoint]) -> CGPoint {
            CGPoint(x: p.map(\.x).reduce(0, +) / CGFloat(p.count), y: p.map(\.y).reduce(0, +) / CGFloat(p.count))
        }
        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

        var le = center(pts(leftEye)), re = center(pts(rightEye))
        if le.x > re.x { swap(&le, &re) }   // image-left first, so roll and "up" are consistent
        let c = pts(contour)
        guard c.count >= 5 else { return nil }
        let chin = c[c.count / 2]
        let noseC = center(pts(nose))
        let jawA = c[Int(Double(c.count - 1) * 0.3)]
        let jawB = c[Int(Double(c.count - 1) * 0.7)]

        let box = VNImageRectForNormalizedRect(face.boundingBox, Int(size.width), Int(size.height))
            .offsetBy(dx: origin.x, dy: origin.y)
        let roll = atan2(re.y - le.y, re.x - le.x)
        // Vision's box spans roughly brows..chin; shift up and enlarge to include the forehead.
        let up = CGPoint(x: -sin(roll), y: cos(roll))
        let shift = box.height * 0.12
        let faceCenter = CGPoint(x: box.midX + up.x * shift, y: box.midY + up.y * shift)

        return FaceInfo(leftEye: le, rightEye: re, eyeRadius: dist(le, re) * 0.36,
                        leftJaw: jawA, rightJaw: jawB,
                        anchor: CGPoint(x: (noseC.x + chin.x) / 2, y: (noseC.y + chin.y) / 2),
                        faceWidth: box.width,
                        faceCenter: faceCenter,
                        faceAxes: CGSize(width: box.width * 0.55, height: box.height * 0.68),
                        roll: roll)
    }
}

final class BeautyEngine {
    static let shared = BeautyEngine()

    let context = CIContext(options: [.cacheIntermediates: false])
    private let skinKernel: CIKernel
    private let warpKernel: CIKernel
    private let styles = StyleRenderer()

    private init() {
        let url = Bundle.main.url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        skinKernel = try! CIKernel(functionName: "beautySkin", fromMetalLibraryData: data)
        warpKernel = try! CIKernel(functionName: "beautyWarp", fromMetalLibraryData: data)
    }

    func process(_ input: CIImage, face: FaceInfo?, params p: BeautyParams) -> CIImage {
        if p.bypass { return input }
        let extent = input.extent
        var img = input

        if let f = face {
            // 1. 瘦脸 + 大眼 (geometry first, so retouching works on the final shape).
            //    Radii are tied to face size so the warp stays on the face, not the background.
            if p.eyes > 0.01 || p.slim > 0.01 {
                let slimR = f.faceWidth * 0.22
                let push = CGFloat(p.slim) * 0.07 * f.faceWidth   // max jaw displacement in px
                func target(_ c: CGPoint) -> CIVector {
                    let dx = f.anchor.x - c.x, dy = f.anchor.y - c.y
                    let len = max(hypot(dx, dy), 1)
                    return CIVector(x: c.x + dx / len * push, y: c.y + dy / len * push)
                }
                let args: [Any] = [
                    img.clampedToExtent(),
                    CIVector(cgPoint: f.leftEye), CIVector(cgPoint: f.rightEye),
                    f.eyeRadius, CGFloat(p.eyes) * 0.15,
                    CIVector(cgPoint: f.leftJaw), target(f.leftJaw),
                    CIVector(cgPoint: f.rightJaw), target(f.rightJaw),
                    slimR,
                ]
                let pad = slimR + f.eyeRadius + 4
                if let out = warpKernel.apply(extent: extent, roiCallback: { _, r in r.insetBy(dx: -pad, dy: -pad) },
                                              arguments: args) {
                    img = out
                }
            }

            // 2. 磨皮 + 美白, face-masked. Whitening is deliberately mild: at 1.0 a mid-tone
            //    skin pixel brightens by roughly 10 percentage points.
            if p.smooth > 0.01 || p.whiten > 0.01 {
                let radius = max(2, f.faceWidth * CGFloat(0.012 + 0.018 * p.smooth))
                let sigmaR = 0.03 + 0.06 * CGFloat(p.smooth)
                let beta = 1 + 1.5 * CGFloat(p.whiten)
                let args: [Any] = [
                    img.clampedToExtent(), radius, CGFloat(p.smooth) * 0.85, sigmaR, beta,
                    CIVector(cgPoint: f.faceCenter),
                    CIVector(x: f.faceAxes.width, y: f.faceAxes.height),
                    CIVector(x: cos(f.roll), y: sin(f.roll)),
                ]
                if let out = skinKernel.apply(extent: extent,
                                              roiCallback: { _, r in r.insetBy(dx: -radius - 2, dy: -radius - 2) },
                                              arguments: args) {
                    img = out
                }
            }
        }

        // 3. 风格滤镜 (whole image, by design)
        img = styles.apply(StylePreset.all[p.style], intensity: p.styleIntensity, to: img)
        return img.cropped(to: extent)
    }
}
