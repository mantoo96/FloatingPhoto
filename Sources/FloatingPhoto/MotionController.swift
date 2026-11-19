import Combine
import CoreMotion
import Foundation

@MainActor
final class FloatingPhotoMotionController: ObservableObject {
    @Published private(set) var offset = CGSize.zero

    private let manager = CMMotionManager()
    private let configuration: FloatingPhotoConfiguration

    init(configuration: FloatingPhotoConfiguration) {
        self.configuration = configuration
    }

    func start() {
        guard configuration.allowsDeviceMotion, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let x = max(-1, min(1, motion.attitude.roll / self.configuration.maximumTilt))
            let y = max(-1, min(1, motion.attitude.pitch / self.configuration.maximumTilt))
            self.offset = CGSize(
                width: CGFloat(x) * self.configuration.intensity,
                height: CGFloat(y) * self.configuration.intensity
            )
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
