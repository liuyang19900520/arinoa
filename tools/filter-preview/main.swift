// Mac preview tool: renders an image through the app's real BeautyEngine (beauty off) with the
// given filter indices at full strength, so filters can be checked without a phone.
//   ./run.sh input.jpg outdir 0 1 2
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let input = CIImage(contentsOf: URL(fileURLWithPath: args[1]))!
let outDir = args[2]
let styles = args.count > 3 ? args[3...].compactMap { Int($0) } : Array(StylePreset.all.indices)
for i in styles {
    var p = BeautyParams()
    p.smooth = 0; p.whiten = 0; p.eyes = 0; p.slim = 0
    p.style = i; p.styleIntensity = 1
    let img = BeautyEngine.shared.process(input, face: nil, params: p)
    let cg = BeautyEngine.shared.context.createCGImage(img, from: input.extent)!
    let url = URL(fileURLWithPath: "\(outDir)/f\(i).png")
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, cg, nil)
    CGImageDestinationFinalize(d)
    print(i, StylePreset.all[i].name, url.path)
}
