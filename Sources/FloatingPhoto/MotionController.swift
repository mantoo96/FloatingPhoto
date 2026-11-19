import Combine
import CoreMotion
import Foundation

@MainActor
final class FloatingPhotoMotionController: ObservableObject {
    @Published private(set) var offset = CGSize.zero

    private let manager = CMMotionManager()
    private let configuration: FloatingPhotoConfiguration
    private var filteredX = CGFloat.zero
    private var filteredY = CGFloat.zero

    init(configuration: FloatingPhotoConfiguration) {
        self.configuration = configuration
    }

    func start() {
        guard configuration.allowsDeviceMotion, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let rawX = self.deadZone(
                max(-1, min(1, motion.attitude.roll / self.configuration.maximumTilt))
            )
            let rawY = self.deadZone(
                max(-1, min(1, motion.attitude.pitch / self.configuration.maximumTilt))
            )

            self.filteredX += (rawX - self.filteredX) * 0.08
            self.filteredY += (rawY - self.filteredY) * 0.08
            self.offset = CGSize(
                width: self.filteredX * self.configuration.intensity,
                height: self.filteredY * self.configuration.intensity
            )
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func deadZone(_ value: CGFloat) -> CGFloat {
        let threshold: CGFloat = 0.045
        guard abs(value) > threshold else { return 0 }
        let sign: CGFloat = value < 0 ? -1 : 1
        return sign * (abs(value) - threshold) / (1 - threshold)
    }
}
