import CoreGraphics
import CoreMotion
import Foundation

/// Tracks how the phone is physically held, from gravity. The UI is portrait-only and the system
/// rotation lock may be on, so UIDevice orientation can't be trusted; Apple Camera uses motion too.
final class OrientationMonitor {
    enum Orientation: String { case portrait, upsideDown, topLeft, topRight }

    private let motion = CMMotionManager()
    private let lock = NSLock()
    private var _current = Orientation.portrait
    var current: Orientation { lock.withLock { _current } }

    func start() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 0.2
        motion.startAccelerometerUpdates(to: OperationQueue()) { [weak self] data, _ in
            guard let self, let g = data?.acceleration else { return }
            // Ignore the phone lying flat, and require a clear tilt so it doesn't flicker at 45°.
            guard abs(g.z) < 0.8, max(abs(g.x), abs(g.y)) > 0.55 else { return }
            let o: Orientation = abs(g.x) > abs(g.y)
                ? (g.x < 0 ? .topLeft : .topRight)      // top edge of the phone points left / right
                : (g.y < 0 ? .portrait : .upsideDown)
            self.lock.withLock { self._current = o }
        }
    }

    /// Counter-clockwise rotation (radians, Core Image coordinates) that turns a captured portrait
    /// frame upright. Front-camera frames are mirrored, which reverses the direction.
    func uprightRotation(frontCamera: Bool) -> CGFloat {
        let quarter = CGFloat.pi / 2
        switch current {
        case .portrait: return 0
        case .upsideDown: return .pi
        case .topLeft: return frontCamera ? -quarter : quarter
        case .topRight: return frontCamera ? quarter : -quarter
        }
    }
}
