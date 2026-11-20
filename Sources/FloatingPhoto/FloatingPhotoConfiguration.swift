import CoreGraphics
import Foundation

/// Controls the motion-parallax scene generated from a still image.
public struct FloatingPhotoConfiguration: Sendable, Hashable {
    /// Overall camera travel. The continuous-depth renderer caps the effective value at 1.
    public var intensity: CGFloat
    /// Tilt range in radians before sensitivity is applied. The default is 0.35 (about 20 degrees).
    public var maximumTilt: CGFloat
    /// Multiplies sub-limit device tilt before the visual travel is capped.
    public var motionSensitivity: CGFloat
    /// Depth-dependent blur strength. Use zero for a sharp image throughout.
    public var backgroundBlur: CGFloat
    /// Scales the depth-dependent blur from 0 to 1.
    public var backgroundBlurOpacity: CGFloat
    /// The centered crop applied to the whole scene at every camera position.
    public var backgroundScale: CGFloat
    /// Foreground contribution to the overall depth range, combined with ``backgroundDepth``.
    public var foregroundDepth: CGFloat
    /// Background contribution to the overall depth range, combined with ``foregroundDepth``.
    public var backgroundDepth: CGFloat
    /// Enables sensor input for ``FloatingPhotoMotion/device``. Fixed offsets and video export remain available.
    public var allowsDeviceMotion: Bool
    /// Legacy edge-fog setting retained for source compatibility with the layered renderer.
    public var edgeFogOpacity: CGFloat

    /// Creates settings for a preview and its exported video.
    ///
    /// - Parameters:
    ///   - intensity: Maximum camera travel multiplier. Defaults to 0.8.
    ///   - maximumTilt: Device tilt range in radians at unit sensitivity. Defaults to 0.35.
    ///   - motionSensitivity: Gain applied to small tilts. Defaults to 1.1.
    ///   - backgroundBlur: Strength of depth-dependent blur. Defaults to 5.
    ///   - backgroundBlurOpacity: Fraction of the blur strength to apply. Defaults to 0.22.
    ///   - backgroundScale: Centered aspect-fill zoom. A value of 1 adds no extra crop.
    ///   - foregroundDepth: Foreground contribution to the depth range. Defaults to 0.82.
    ///   - backgroundDepth: Background contribution to the depth range. Defaults to 0.12.
    ///   - allowsDeviceMotion: Whether the view can start device-motion updates.
    ///   - edgeFogOpacity: Legacy setting accepted for compatibility.
    public init(
        intensity: CGFloat = 0.8,
        maximumTilt: CGFloat = 0.35,
        motionSensitivity: CGFloat = 1.1,
        backgroundBlur: CGFloat = 5,
        backgroundBlurOpacity: CGFloat = 0.22,
        backgroundScale: CGFloat = 1.02,
        foregroundDepth: CGFloat = 0.82,
        backgroundDepth: CGFloat = 0.12,
        allowsDeviceMotion: Bool = true,
        edgeFogOpacity: CGFloat = 0.10
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
        self.edgeFogOpacity = min(1, max(0, edgeFogOpacity))
    }

    /// The standard tilt response and depth strength.
    public static let `default` = Self()

    /// A preset with lower camera travel and a smaller crop.
    public static let subtle = Self(
        intensity: 0.35,
        maximumTilt: 0.25,
        backgroundBlur: 6,
        backgroundBlurOpacity: 0.18,
        backgroundScale: 1.01,
        foregroundDepth: 0.58,
        backgroundDepth: 0.06,
        edgeFogOpacity: 0.08
    )
}

/// The outcome of preparing a photo. A preview also uses these phases for its on-screen overlay.
public enum FloatingPhotoPhase: Equatable, Sendable {
    /// The scene has been created and is waiting for preparation to begin.
    case idle
    /// Depth preparation is underway, or the preview is waiting to present its first frame.
    case processing
    /// A usable depth field and renderer are available. A preview reports this after its first presented frame.
    case ready
    /// Preparation finished with a static photo fallback. Video export is available.
    case degraded
    /// The source image could not be prepared. Provide another image to create a new scene.
    case failed
}

/// The camera input used by a preview. Reduce Motion centers the preview in either mode.
public enum FloatingPhotoMotion: Sendable, Equatable {
    /// Follows tilt relative to the initial device orientation while the preview is active.
    case device
    /// Holds a fixed horizontal and vertical offset. A vector of length 1 reaches maximum travel.
    case staticOffset(x: CGFloat, y: CGFloat)
}
