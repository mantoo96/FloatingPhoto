import Foundation

/// Image and movie-export errors surfaced by FloatingPhoto.
public enum FloatingPhotoError: LocalizedError, Equatable {
    /// The input does not contain usable image data.
    case invalidImage
    /// The scene has no prepared renderer for export.
    case sceneNotPrepared
    /// The output size, duration, or frame rate is invalid.
    case unsupportedVideoSize
    /// A frame could not be rendered or the movie encoder could not finish.
    case exportFailed

    /// A user-facing description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The image could not be prepared for floating-photo rendering."
        case .sceneNotPrepared:
            return "Prepare the floating-photo scene before exporting it."
        case .unsupportedVideoSize:
            return "The requested video size, duration, or frame rate is invalid."
        case .exportFailed:
            return "The floating-photo video could not be exported."
        }
    }
}
