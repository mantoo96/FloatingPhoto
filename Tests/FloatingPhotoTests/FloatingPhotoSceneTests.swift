import Combine
import FloatingPhoto
import UIKit
import XCTest

final class FloatingPhotoSceneTests: XCTestCase {
    @MainActor
    func testConcurrentClientsPrepareOnceAndCanExportTheSameScene() async throws {
        let size = CGSize(width: 160, height: 120)
        let image = UIGraphicsImageRenderer(size: size).image { drawing in
            UIColor.white.setFill()
            drawing.fill(CGRect(origin: .zero, size: size))
            UIColor.blue.setFill()
            drawing.fill(CGRect(x: 40, y: 20, width: 60, height: 70))
        }
        let scene = FloatingPhotoScene(image: image)
        var phases: [FloatingPhotoPhase] = []
        let observation = scene.$phase.sink { phases.append($0) }
        defer { observation.cancel() }
        XCTAssertFalse(scene.canExport)

        async let preview: Void = scene.prepare()
        async let exporter: Void = scene.prepare()
        _ = await (preview, exporter)
        await scene.prepare()

        XCTAssertTrue(scene.phase == .ready || scene.phase == .degraded)
        XCTAssertEqual(phases, [.idle, .processing, scene.phase])
        XCTAssertTrue(scene.canExport)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        try await scene.exportVideo(to: file, size: size, duration: 0.5, frameRate: 8)
        XCTAssertGreaterThan(try Data(contentsOf: file).count, 0)
    }

    @MainActor
    func testInvalidPhotoPublishesFailureAndKeepsExportUnavailable() async throws {
        let scene = FloatingPhotoScene(image: UIImage())
        await scene.prepare()
        XCTAssertEqual(scene.phase, .failed)
        XCTAssertFalse(scene.canExport)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try await scene.exportVideo(to: file, size: CGSize(width: 160, height: 120))
            XCTFail("An unusable photo should not start a movie export")
        } catch let error as FloatingPhotoError {
            XCTAssertEqual(error, .sceneNotPrepared)
        }
    }
}
