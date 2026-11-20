import CoreGraphics
import Foundation

/// Controls the motion-parallax scene generated from a still image.
public struct FloatingPhotoConfiguration: Sendable, Hashable {
    public var intensity: CGFloat
    public var maximumTilt: CGFloat
    /// Multiplies sub-limit device tilt before the visual travel is capped.
    public var motionSensitivity: CGFloat
    /// Softens transitions in the depth field, in combination with `backgroundBlurOpacity`.
    public var backgroundBlur: CGFloat
    public var backgroundBlurOpacity: CGFloat
    /// The centered crop applied to the whole scene at every camera position.
    public var backgroundScale: CGFloat
    public var foregroundDepth: CGFloat
    public var backgroundDepth: CGFloat
    public var allowsDeviceMotion: Bool

    public init(
        intensity: CGFloat = 0.8,
        maximumTilt: CGFloat = 0.35,
        motionSensitivity: CGFloat = 1.1,
        backgroundBlur: CGFloat = 5,
        backgroundBlurOpacity: CGFloat = 0.22,
        backgroundScale: CGFloat = 1,
        foregroundDepth: CGFloat = 0.48,
        backgroundDepth: CGFloat = 0.64,
        allowsDeviceMotion: Bool = true
    ) {
        self.intensity = max(0, intensity)
        self.maximumTilt = max(0.01, maximumTilt)
        self.motionSensitivity = max(0, motionSensitivity)
        self.backgroundBlur = max(0, backgroundBlur)
        self.backgroundBlurOpacity = min(1, max(0, backgroundBlurOpacity))
        self.backgroundScale = max(1, backgroundScale)
        self.foregroundDepth = max(0, foregroundDepth)
        self.backgroundDepth = max(0, backgroundDepth)
        self.allowsDeviceMotion = allowsDeviceMotion
    }

    public static let `default` = Self()

    public static let subtle = Self(
        intensity: 0.35,
        maximumTilt: 0.25,
        backgroundBlur: 6,
        backgroundBlurOpacity: 0.18,
        backgroundScale: 1,
        foregroundDepth: 0.48,
        backgroundDepth: 0.64
    )
}

public enum FloatingPhotoPhase: Equatable, Sendable {
    case idle
    case processing
    case ready
    case degraded
    case failed
}

public enum FloatingPhotoMotion: Sendable, Equatable {
    case device
    case staticOffset(x: CGFloat, y: CGFloat)
}
