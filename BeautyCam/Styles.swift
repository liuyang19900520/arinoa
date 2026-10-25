import CoreImage
import CoreImage.CIFilterBuiltins
import simd
import ImageIO
import SwiftUI

/// Hue bands for per-color adjustments (like the HSL panel in Lightroom).
enum HueBand: CaseIterable {
    case red, orange, yellow, green, cyan, blue, magenta
    /// Band center in degrees. Orange (~30°) is where skin tones sit.
    var center: Float {
        switch self {
        case .red: 0
        case .orange: 30
        case .yellow: 60
        case .green: 120
        case .cyan: 180
        case .blue: 225
        case .magenta: 300
        }
    }
}

struct HueAdjust {
    var hue: Float = 0      // degrees of hue rotation
    var sat: Float = 1      // saturation multiplier
    var lum: Float = 0      // brightness change, scaled by the pixel's saturation (neutrals untouched)
}

/// iPhone Photos "Edit" sliders, each -100...100 as shown in the app, so recipes found online can be
/// typed in directly. Apple doesn't publish its algorithms; these are approximations of each control.
/// Definition (清晰度) and Vignette (暈邊) are local/spatial and handled outside the LUT.
struct PhotosAdjust {
    var dramatic: Float = 0     // 戲劇 filter strength 0...100
    var exposure: Float = 0     // 曝光
    var brilliance: Float = 0   // 增豔
    var highlights: Float = 0   // 亮部
    var shadows: Float = 0      // 陰影
    var contrast: Float = 0     // 對比
    var brightness: Float = 0   // 亮度
    var blackPoint: Float = 0   // 黑點
    var saturation: Float = 0   // 飽和度
    var vibrance: Float = 0     // 自然飽和度
    var warmth: Float = 0       // 色溫
    var tint: Float = 0         // 色調 (+ magenta, - green)

    func apply(_ input: SIMD3<Float>) -> SIMD3<Float> {
        var c = input
        let lumaW = SIMD3<Float>(0.299, 0.587, 0.114)
        func tone(_ f: (Float) -> Float) { c = SIMD3(f(c.x), f(c.y), f(c.z)) }

        // 戲劇 (Dramatic): firmer S-contrast, held-back highlights, slightly muted color.
        let d = dramatic / 100
        let ex = exposure / 100, br = brilliance / 100, hi = highlights / 100, sh = shadows / 100
        let co = contrast / 100, bt = brightness / 100, bp = blackPoint / 100

        tone { x in x * pow(2, ex) }
        // Black point: + crushes the darkest tones toward black.
        tone { x in max(0, (x - bp * 0.08) / (1 - bp * 0.08)) }
        // Brilliance: lifts shadows and holds back highlights (Apple also adds local contrast).
        let shadowsTotal = sh + br * 0.6 + d * 0.05
        let highlightsTotal = hi - br * 0.4 - d * 0.25
        tone { x in x + shadowsTotal * 1.5 * x * (1 - x) * (1 - x) }
        tone { x in x + highlightsTotal * 1.5 * x * x * (1 - x) }
        // Brightness: midtone gamma.
        tone { x in pow(max(x, 0), 1 - bt * 0.5) }
        // Contrast: linear around mid-grey, plus the Dramatic S-curve.
        tone { x in 0.5 + (x - 0.5) * (1 + co * 0.6) }
        if d > 0 {
            tone { x in
                let y = min(max(x, 0), 1)
                return y + (y * y * (3 - 2 * y) - y) * d * 0.6
            }
        }

        // White balance.
        let w = warmth / 100, t = tint / 100
        c *= SIMD3(1 + w * 0.2, 1 - t * 0.15, 1 - w * 0.2)

        // Saturation, vibrance (protects already-saturated colors), Dramatic desaturation.
        let l = (c * lumaW).sum()
        let chroma = max(0, c.max() - c.min())
        let sat = (1 + saturation / 100) * (1 + vibrance / 100 * (1 - min(chroma * 2, 1))) * (1 - d * 0.15)
        c = SIMD3(repeating: l) + (c - SIMD3(repeating: l)) * sat
        return simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 1))
    }
}

/// Color grade evaluated in gamma (sRGB-encoded) space, baked into a 3D LUT.
struct Grade {
    /// Per-channel tone curves (R, G, B), 11 evenly spaced knots on 0...1, linearly interpolated.
    /// Applied first. Used for looks fitted from real photos.
    var rgbCurves: [[Float]]?
    var photos: PhotosAdjust?      // iPhone Photos recipe, applied after rgbCurves
    var exposure: Float = 0        // stops
    var contrast: Float = 1        // linear contrast around mid-grey
    var curve: Float = 0           // film S-curve: + firmer toe/shoulder, - flatter
    var saturation: Float = 1
    var temperature: Float = 0     // + warm, - cool
    var tint: Float = 0            // + magenta/pink, - green
    var fade: Float = 0            // lifted blacks (matte)
    var highlightSoft: Float = 0   // compresses whites so nothing clips harshly (film shoulder)
    var colorContrast: Float = 0   // darkens dark, saturated colors (Classic Neg "veiled" look)
    var shadowTint = SIMD3<Float>(0, 0, 0)
    var highlightTint = SIMD3<Float>(0, 0, 0)
    var hues: [HueBand: HueAdjust] = [:]
    var mono = false

    func apply(_ input: SIMD3<Float>) -> SIMD3<Float> {
        var c = input
        if let k = rgbCurves {
            func f(_ x: Float, _ knots: [Float]) -> Float {
                let t = min(max(x, 0), 1) * 10
                let i = min(Int(t), 9)
                return knots[i] + (knots[i + 1] - knots[i]) * (t - Float(i))
            }
            c = SIMD3(f(c.x, k[0]), f(c.y, k[1]), f(c.z, k[2]))
        }
        c = (photos?.apply(c) ?? c) * pow(2, exposure)
        c += SIMD3(temperature * 0.08, -tint * 0.05, -temperature * 0.08)
        c = simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 1))
        if !hues.isEmpty { c = applyHues(c) }

        let lumaW = SIMD3<Float>(0.299, 0.587, 0.114)
        if mono { c = SIMD3(repeating: (c * lumaW).sum()) }
        c = (c - 0.5) * contrast + 0.5
        if curve != 0 {
            let x = simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 1))
            let s = x * x * (3 - 2 * x)
            c = x + (s - x) * curve
        }
        if colorContrast > 0 {
            let l = (c * lumaW).sum()
            let chroma = (c.max() - c.min())
            c *= 1 - colorContrast * chroma * (1 - l) * (1 - l)
        }
        var l = (c * lumaW).sum()
        c = SIMD3(repeating: l) + (c - SIMD3(repeating: l)) * saturation
        l = max(0, min(1, (c * lumaW).sum()))
        c += shadowTint * (1 - l) * (1 - l) + highlightTint * l * l
        c = c * (1 - fade) + fade
        if highlightSoft > 0 {
            let x = simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 1))
            c = x * (1 - highlightSoft * x * x)
        }
        return simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 1))
    }

    /// Per-hue rotation / saturation / brightness with smooth, overlapping band weights.
    private func applyHues(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        var (h, s, v) = Self.rgbToHsv(rgb)
        guard s > 0.0001 else { return rgb }
        var dh: Float = 0, ds: Float = 0, dl: Float = 0, wsum: Float = 0
        for band in HueBand.allCases {
            var d = abs(h - band.center)
            d = min(d, 360 - d)
            let w = max(0, 1 - d / 45)
            guard w > 0 else { continue }
            let a = hues[band] ?? HueAdjust()
            dh += w * a.hue; ds += w * (a.sat - 1); dl += w * a.lum; wsum += w
        }
        if wsum > 0 { dh /= wsum; ds /= wsum; dl /= wsum }
        h = (h + dh).truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        let sNew = min(1, s * (1 + ds))
        v = min(1, max(0, v * (1 + dl * s)))
        return Self.hsvToRgb(h, sNew, v)
    }

    private static func rgbToHsv(_ c: SIMD3<Float>) -> (Float, Float, Float) {
        let mx = c.max(), mn = c.min(), d = mx - mn
        var h: Float = 0
        if d > 0 {
            if mx == c.x { h = 60 * ((c.y - c.z) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == c.y { h = 60 * ((c.z - c.x) / d + 2) }
            else { h = 60 * ((c.x - c.y) / d + 4) }
        }
        if h < 0 { h += 360 }
        return (h, mx > 0 ? d / mx : 0, mx)
    }

    private static func hsvToRgb(_ h: Float, _ s: Float, _ v: Float) -> SIMD3<Float> {
        let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let rgb: SIMD3<Float>
        switch h {
        case ..<60: rgb = SIMD3(c, x, 0)
        case ..<120: rgb = SIMD3(x, c, 0)
        case ..<180: rgb = SIMD3(0, c, x)
        case ..<240: rgb = SIMD3(0, x, c)
        case ..<300: rgb = SIMD3(x, 0, c)
        default: rgb = SIMD3(c, 0, x)
        }
        return rgb + m
    }
}

struct StylePreset: Identifiable {
    let id: Int
    let name: String
    var grade = Grade()
    var grain: Float = 0
    var vignette: Float = 0
    var defaultIntensity: Float = 0.8   // strength slider value when the filter is picked

    /// Swatch for the style picker: the grade applied to a mid skin tone.
    var swatch: Color {
        let c = grade.apply(SIMD3(0.85, 0.66, 0.55))
        return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }

    private init(_ name: String, _ grade: Grade = Grade(), grain: Float = 0, vignette: Float = 0,
                 defaultIntensity: Float = 0.8, id: Int = 0) {
        self.id = id; self.name = name; self.grade = grade; self.grain = grain; self.vignette = vignette
        self.defaultIntensity = defaultIntensity
    }

    /// Fujifilm-style looks are approximations built from Fujifilm's published descriptions of each
    /// film simulation (tone character, color bias, per-color behavior), not Fujifilm's own LUTs.
    private static let definitions: [StylePreset] = [
        StylePreset("原图"),

        // Fitted from real photos: the same room shot on a Fujifilm camera vs. this app (15 matched
        // patches: wall, shirt, sofa, trousers, skin, hair, TV black, red/pink objects). Per-channel
        // curves carry its look: warm cream whites, warmer amber mids/shadows, lifted shadows,
        // held-back highlights. Reds/oranges get extra brightness, as in the Fujifilm shots.
        StylePreset("富士", Grade(
            rgbCurves: [
                [0.043, 0.181, 0.323, 0.468, 0.617, 0.725, 0.796, 0.850, 0.886, 0.919, 0.960],
                [0.000, 0.154, 0.282, 0.365, 0.445, 0.566, 0.680, 0.739, 0.773, 0.813, 0.869],
                [0.000, 0.086, 0.198, 0.278, 0.372, 0.495, 0.571, 0.635, 0.689, 0.733, 0.799],
            ],
            hues: [.red: HueAdjust(lum: 0.15), .orange: HueAdjust(lum: 0.06)]),
            defaultIntensity: 0.36),

        StylePreset("自然", Grade(exposure: 0.1, saturation: 1.03)),
        StylePreset("奶油肌", Grade(contrast: 0.88, saturation: 0.92, temperature: 0.25, fade: 0.06,
                                 highlightTint: SIMD3(0.03, 0.015, 0))),
        StylePreset("清透", Grade(exposure: 0.25, contrast: 0.95, saturation: 1.05, temperature: -0.1)),
        StylePreset("冷白皮", Grade(exposure: 0.15, temperature: -0.4, tint: 0.1)),
        StylePreset("日系胶片", Grade(contrast: 0.9, saturation: 0.85, temperature: -0.05, fade: 0.1,
                                  shadowTint: SIMD3(0, 0.04, 0.05), highlightTint: SIMD3(0.03, 0.02, 0)),
                    grain: 0.5),
        StylePreset("韩系", Grade(exposure: 0.15, contrast: 0.85, saturation: 0.9, tint: 0.25, fade: 0.04)),
        StylePreset("港风复古", Grade(contrast: 1.2, saturation: 1.1, temperature: 0.45,
                                  shadowTint: SIMD3(0.04, 0, -0.02), highlightTint: SIMD3(0.05, 0.02, -0.03)),
                    grain: 0.3, vignette: 0.8),
        StylePreset("森系", Grade(exposure: 0.05, saturation: 0.75, tint: -0.2, fade: 0.05,
                                shadowTint: SIMD3(0, 0.03, 0.01))),
        StylePreset("黑白", Grade(contrast: 1.25, mono: true), grain: 0.3, vignette: 0.4),
    ]

    /// `id` is the index, which BeautyParams.style stores.
    static let all: [StylePreset] = definitions.enumerated().map { i, p in
        StylePreset(p.name, p.grade, grain: p.grain, vignette: p.vignette, defaultIntensity: p.defaultIntensity, id: i)
    }
}

/// Applies a style (LUT + grain + vignette). LUTs are built once per style and cached.
final class StyleRenderer {
    private static let cubeSize = 32
    private var cubes: [Int: (Int, Data)] = [:]
    private let lock = NSLock()
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private lazy var noise = CIFilter.randomGenerator().outputImage!

    /// Returns (dimension, data). Prefers `LUTs/<name>.png` (standard 512x512, 64-cube, 8x8 tiles)
    /// in the bundle, so real filter LUTs can be dropped in; otherwise bakes the procedural grade.
    private func cube(for style: StylePreset) -> (Int, Data) {
        lock.withLock {
            if let cached = cubes[style.id] { return cached }
            if let url = Bundle.main.url(forResource: style.name, withExtension: "png", subdirectory: "LUTs"),
               let d = Self.loadLUTImage(url) {
                cubes[style.id] = (64, d)
                return (64, d)
            }
            let n = Self.cubeSize
            var values = [Float](repeating: 0, count: n * n * n * 4)
            let s = Float(n - 1)
            var i = 0
            for b in 0..<n { for g in 0..<n { for r in 0..<n {
                let c = style.grade.apply(SIMD3(Float(r) / s, Float(g) / s, Float(b) / s))
                values[i] = c.x; values[i + 1] = c.y; values[i + 2] = c.z; values[i + 3] = 1
                i += 4
            } } }
            let d = values.withUnsafeBufferPointer { Data(buffer: $0) }
            cubes[style.id] = (n, d)
            return (n, d)
        }
    }

    private static func loadLUTImage(_ url: URL) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
              cg.width == 512, cg.height == 512 else { return nil }
        var px = [UInt8](repeating: 0, count: 512 * 512 * 4)
        guard let ctx = CGContext(data: &px, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 512 * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        var values = [Float](repeating: 0, count: 64 * 64 * 64 * 4)
        var i = 0
        for b in 0..<64 { for g in 0..<64 { for r in 0..<64 {
            let x = (b % 8) * 64 + r, y = (b / 8) * 64 + g
            let o = (y * 512 + x) * 4
            values[i] = Float(px[o]) / 255; values[i + 1] = Float(px[o + 1]) / 255
            values[i + 2] = Float(px[o + 2]) / 255; values[i + 3] = 1
            i += 4
        } } }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    func apply(_ style: StylePreset, intensity: Float, to image: CIImage) -> CIImage {
        guard style.id != 0, intensity > 0.01 else { return image }
        let extent = image.extent
        let (dim, data) = cube(for: style)
        let f = CIFilter.colorCubeWithColorSpace()
        f.inputImage = image
        f.cubeDimension = Float(dim)
        f.cubeData = data
        f.colorSpace = srgb
        var img = f.outputImage ?? image

        if style.grain > 0 {
            // Shift the noise each frame so video grain looks alive, not stuck to the screen.
            let a = CGFloat(style.grain) * 0.18
            let shifted = noise.transformed(by: CGAffineTransform(translationX: .random(in: 0...512), y: .random(in: 0...512)))
            let mono = shifted.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: a, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: a, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: a, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0.5 - a / 2, y: 0.5 - a / 2, z: 0.5 - a / 2, w: 0),
            ]).cropped(to: extent)
            img = mono.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: img])
        }
        if style.vignette > 0 {
            // Soft radial darkening: untouched inside ~45% of the half-diagonal, corners darkened by
            // up to `vignette` × 45%.
            let center = CIVector(x: extent.midX, y: extent.midY)
            let halfDiag = hypot(extent.width, extent.height) / 2
            let edge = CGFloat(1 - style.vignette * 0.45)
            let mask = CIFilter.radialGradient()
            mask.center = CGPoint(x: center.x, y: center.y)
            mask.radius0 = Float(halfDiag * 0.45)
            mask.radius1 = Float(halfDiag)
            mask.color0 = CIColor(red: 1, green: 1, blue: 1)
            mask.color1 = CIColor(red: edge, green: edge, blue: edge)
            if let m = mask.outputImage?.cropped(to: extent) {
                img = m.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: img])
            }
        }
        if intensity < 0.99 {
            let mix = CIFilter.dissolveTransition()
            mix.inputImage = image
            mix.targetImage = img
            mix.time = intensity
            img = mix.outputImage ?? img
        }
        return img.cropped(to: extent)
    }
}
