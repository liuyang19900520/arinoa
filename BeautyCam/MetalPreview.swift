import AVKit
import MetalKit
import SwiftUI

/// Draws the most recent CIImage into an MTKView.
final class PreviewRenderer: NSObject, MTKViewDelegate {
    let device = MTLCreateSystemDefaultDevice()!
    private lazy var queue = device.makeCommandQueue()!
    private lazy var context = CIContext(mtlCommandQueue: queue, options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var _image: CIImage?
    var fill = true

    var image: CIImage? {
        get { lock.withLock { _image } }
        set { lock.withLock { _image = newValue } }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let image, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer() else { return }
        let size = view.drawableSize
        let e = image.extent
        let sx = size.width / e.width, sy = size.height / e.height
        let s = fill ? max(sx, sy) : min(sx, sy)
        var img = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        img = img.transformed(by: CGAffineTransform(translationX: (size.width - img.extent.width) / 2 - img.extent.minX,
                                                    y: (size.height - img.extent.height) / 2 - img.extent.minY))
        let dest = CIRenderDestination(width: Int(size.width), height: Int(size.height),
                                       pixelFormat: view.colorPixelFormat, commandBuffer: buffer,
                                       mtlTextureProvider: { drawable.texture })
        _ = try? context.startTask(toClear: dest)
        _ = try? context.startTask(toRender: img, to: dest)
        buffer.present(drawable)
        buffer.commit()
    }
}

struct MetalPreview: UIViewRepresentable {
    let renderer: PreviewRenderer
    /// Volume-button / Camera Control shutter presses (iOS 17.2+).
    var onCaptureEvent: (() -> Void)?

    final class Coordinator { var onCaptureEvent: (() -> Void)? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 30
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = renderer
        if #available(iOS 17.2, *) {
            let coordinator = context.coordinator
            view.addInteraction(AVCaptureEventInteraction { event in
                if event.phase == .ended { coordinator.onCaptureEvent?() }
            })
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.onCaptureEvent = onCaptureEvent
    }
}
