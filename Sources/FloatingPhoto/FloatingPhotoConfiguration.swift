import CoreGraphics
import Foundation

/// Controls the motion-parallax scene generated from a still image.
public struct FloatingPhotoConfiguration: Sendable, Hashable {
    public var intensity: CGFloat
    public var maximumTilt: CGFloat
    public var backgroundBlur: CGFloat
    public var backgroundBlurOpacity: CGFloat
    public var backgroundScale: CGFloat
    public var foregroundDepth: CGFloat
    public var backgroundDepth: CGFloat
    public var allowsDeviceMotion: Bool

    public init(
        intensity: CGFloat = 0.55,
        maximumTilt: CGFloat = 0.22,
        backgroundBlur: CGFloat = 5,
        backgroundBlurOpacity: CGFloat = 0.22,
        backgroundScale: CGFloat = 1.06,
        foregroundDepth: CGFloat = 1.15,
        backgroundDepth: CGFloat = 0.04,
        allowsDeviceMotion: Bool = true
    ) {
        self.intensity = max(0, intensity)
        self.maximumTilt = max(0.01, maximumTilt)
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
        backgroundScale: 1.04,
        foregroundDepth: 0.8,
        backgroundDepth: 0.03
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
