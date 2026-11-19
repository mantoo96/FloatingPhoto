import Foundation

public enum FloatingPhotoError: LocalizedError, Equatable {
    case invalidImage
    case sceneNotPrepared
    case unsupportedVideoSize
    case exportFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The image could not be prepared for floating-photo rendering."
        case .sceneNotPrepared:
            return "Prepare the floating-photo scene before exporting it."
        case .unsupportedVideoSize:
            return "The requested video size is invalid."
        case .exportFailed:
            return "The floating-photo video could not be exported."
        }
    }
}
