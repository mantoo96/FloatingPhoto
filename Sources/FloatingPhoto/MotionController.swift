import Combine
import CoreMotion
import simd

struct PhotoTilt {
    private static let responseTime: TimeInterval = 0.04
    private var reference: simd_quatd?
    private var previousTime: TimeInterval?
    private var filtered = SIMD2<Double>.zero

    mutating func sample(
        _ attitude: simd_quatd,
        time: TimeInterval,
        maximumTilt: CGFloat,
        motionSensitivity: CGFloat = 1.1
    ) -> CGSize {
        guard let reference, let previousTime else {
            reference = attitude
            previousTime = time
            return .zero
        }
        self.previousTime = time
        // The opening viewing direction expressed in the current device axes also handles rotation into landscape.
        let normal = (attitude.inverse * reference).act(SIMD3(0, 0, 1))
        var raw = SIMD2(-atan2(normal.x, normal.z), atan2(normal.y, normal.z))
        let magnitude = simd_length(raw)
        let limit = max(0.01, Double(maximumTilt))
        let deadZone = min(0.025, limit * 0.2)
        if magnitude > deadZone {
            let normalizedMagnitude = min(
                1,
                (magnitude - deadZone) / (limit - deadZone) * Double(max(0, motionSensitivity))
            )
            raw *= normalizedMagnitude / magnitude
        } else {
            raw = .zero
        }
        let weight = 1 - exp(-max(0, time - previousTime) / Self.responseTime)
        filtered += (raw - filtered) * weight
        if simd_distance(filtered, raw) < 0.0005 { filtered = raw }
        return CGSize(width: filtered.x, height: filtered.y)
    }
}

@MainActor
final class FloatingPhotoMotionController: ObservableObject {
    @Published private(set) var offset = CGSize.zero
    private let manager = CMMotionManager()
    private let configuration: FloatingPhotoConfiguration
    private var tilt = PhotoTilt()

    init(configuration: FloatingPhotoConfiguration) { self.configuration = configuration }

    func start() {
        guard configuration.allowsDeviceMotion, manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        tilt = PhotoTilt()
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion, self.manager.isDeviceMotionActive else { return }
            let q = motion.attitude.quaternion
            let sample = self.tilt.sample(
                simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w),
                time: motion.timestamp,
                maximumTilt: self.configuration.maximumTilt,
                motionSensitivity: self.configuration.motionSensitivity
            )
            if self.offset != sample { self.offset = sample }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        tilt = PhotoTilt()
        if offset != .zero { offset = .zero }
    }
}
