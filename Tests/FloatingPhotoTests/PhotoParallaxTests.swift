import AVFoundation
import CoreImage
import Metal
import simd
import XCTest
@testable import FloatingPhoto

final class PhotoParallaxTests: XCTestCase {
    private let size = CGSize(width: 256, height: 176)
    private var bounds: CGRect { CGRect(origin: .zero, size: size) }
    private var patch: CGRect { CGRect(x: 64, y: 16, width: 80, height: 56) }
    private var depth: CIImage {
        CIImage(color: .white).cropped(to: patch).composited(over: CIImage(color: .black).cropped(to: bounds))
    }
    private var mask: CIImage { depth }
    private var photo: CIImage {
        CIImage(color: .red).cropped(to: patch).composited(over: CIImage(color: .green).cropped(to: bounds))
    }

    func testOpeningWithPhoneUprightAndSmallTremorAreNeutral() {
        var tilt = PhotoTilt()
        let upright = simd_quatd(angle: 1.2, axis: SIMD3(1, 0, 0))
        XCTAssertEqual(tilt.sample(upright, time: 0, maximumTilt: 0.35), .zero)
        let tremor = simd_quatd(angle: 0.01, axis: SIMD3(0, 1, 0))
        XCTAssertEqual(tilt.sample(upright * tremor, time: 1, maximumTilt: 0.35), .zero)
        let turn = simd_quatd(angle: 0.5, axis: SIMD3(0, 1, 0))
        let moved = tilt.sample(upright * turn, time: 2, maximumTilt: 0.35)
        XCTAssertGreaterThan(moved.width, 0.9)
        XCTAssertEqual(moved.height, 0, accuracy: 0.0001)
    }

    func testMotionSensitivityRaisesSubmaxResponseWithoutChangingMaximum() {
        let upright = simd_quatd(angle: 1.2, axis: SIMD3(1, 0, 0))
        let smallTurn = upright * simd_quatd(angle: 0.1, axis: SIMD3(0, 1, 0))

        var normal = PhotoTilt()
        _ = normal.sample(upright, time: 0, maximumTilt: 0.35)
        let normalResponse = normal.sample(smallTurn, time: 1, maximumTilt: 0.35, motionSensitivity: 1)

        var sensitive = PhotoTilt()
        _ = sensitive.sample(upright, time: 0, maximumTilt: 0.35)
        let sensitiveResponse = sensitive.sample(smallTurn, time: 1, maximumTilt: 0.35, motionSensitivity: 1.1)

        XCTAssertEqual(sensitiveResponse.width, normalResponse.width * 1.1, accuracy: 0.01)

        let largeTurn = upright * simd_quatd(angle: 0.5, axis: SIMD3(0, 1, 0))
        let normalMaximum = normal.sample(largeTurn, time: 2, maximumTilt: 0.35, motionSensitivity: 1)
        let sensitiveMaximum = sensitive.sample(largeTurn, time: 2, maximumTilt: 0.35, motionSensitivity: 1.1)
        XCTAssertEqual(sensitiveMaximum.width, normalMaximum.width, accuracy: 0.0001)
    }

    func testMotionResponseReachesTheSceneBeforeThePhoneStopsMoving() {
        let upright = simd_quatd(angle: 1.2, axis: SIMD3(1, 0, 0))
        let turn = upright * simd_quatd(angle: 0.2, axis: SIMD3(0, 1, 0))
        var tilt = PhotoTilt()
        _ = tilt.sample(upright, time: 0, maximumTilt: 0.35)
        let firstFrame = tilt.sample(turn, time: 1.0 / 60.0, maximumTilt: 0.35)
        let settled = tilt.sample(turn, time: 1, maximumTilt: 0.35)

        XCTAssertGreaterThan(firstFrame.width, settled.width * 0.3)
        XCTAssertGreaterThan(tilt.sample(turn, time: 1.1, maximumTilt: 0.35).width, settled.width * 0.88)
    }

    func testCameraUsesTiltMagnitudeUntilTheMaximumTravel() {
        let config = FloatingPhotoConfiguration()
        let surface = PhotoSurface(imageSize: size, depth: depth, configuration: config, context: FloatingPhotoRenderer.context)
        let half = surface.camera(at: CGSize(width: 0.5, height: 0), canvas: size, configuration: config)
        let full = surface.camera(at: CGSize(width: 1, height: 0), canvas: size, configuration: config)
        let beyond = surface.camera(at: CGSize(width: 2, height: 0), canvas: size, configuration: config)

        XCTAssertEqual(half.z, full.z * 0.5, accuracy: 0.0001)
        XCTAssertEqual(beyond.z, full.z, accuracy: 0.0001)
    }

    func testDepthCannotFoldOrUncoverCanvasEvenWithLegacyExtremeSettings() {
        let config = FloatingPhotoConfiguration(intensity: 12, backgroundScale: 1, foregroundDepth: 10, backgroundDepth: 10)
        let surface = PhotoSurface(imageSize: size, depth: depth, configuration: config, context: FloatingPhotoRenderer.context)
        XCTAssertTrue(surface.hasDepth)
        for canvas in [size, CGSize(width: 360, height: 760), CGSize(width: 960, height: 300)] {
            for direction in [CGSize(width: 1, height: 1), CGSize(width: -1, height: 1), CGSize(width: 1, height: -1), CGSize(width: -1, height: -1), CGSize(width: 100, height: 0)] {
                let camera = surface.camera(at: direction, canvas: canvas, configuration: config)
                let projected = surface.vertices.map { v -> SIMD2<Float> in
                    if v.x == 0 || v.x == 1 || v.y == 0 || v.y == 1 { XCTAssertEqual(v.z, 0) }
                    return SIMD2((2 * v.x - 1) * camera.x + v.z * camera.z, (2 * v.y - 1) * camera.y + v.z * camera.w)
                }
                var minArea = Float.greatestFiniteMagnitude
                for i in stride(from: 0, to: surface.indices.count, by: 3) {
                    let a = projected[Int(surface.indices[i])]
                    let ab = projected[Int(surface.indices[i+1])] - a, ac = projected[Int(surface.indices[i+2])] - a
                    minArea = min(minArea, ab.x * ac.y - ab.y * ac.x)
                }
                XCTAssertGreaterThan(minArea, 0)
            }
        }
    }

    func testFlatDepthDegrades() {
        let surface = PhotoSurface(imageSize: size, depth: CIImage(color: .white).cropped(to: bounds), configuration: .default, context: FloatingPhotoRenderer.context)
        XCTAssertFalse(surface.hasDepth)
    }

    func testRenderedPhotoKeepsOneSubjectAtNeutralAndBothTiltLimits() throws {
        let configuration = FloatingPhotoConfiguration(
            intensity: 1,
            backgroundBlur: 0,
            backgroundBlurOpacity: 0,
            backgroundScale: 1,
            foregroundDepth: 1,
            backgroundDepth: 0,
            edgeFogOpacity: 0
        )
        let renderer = FloatingPhotoRenderer(
            source: photo,
            depth: depth,
            foregroundMask: mask,
            configuration: configuration
        )
        let device = try XCTUnwrap(renderer.device)
        let width = Int(size.width), height = Int(size.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        for x in [0, -1, 1] {
            let commands = try XCTUnwrap(renderer.frame(at: CGSize(width: x, height: 0), into: target))
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertEqual(commands.status, .completed)
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            target.getBytes(&bytes, bytesPerRow: 4 * width, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            var firstX = width, lastX = -1, count = 0, area = 0, mismatches = 0, uncovered = 0
            for y in 0..<height {
                for col in 0..<width {
                    let p = (y * width + col) * 4
                    let red = bytes[p+2] > bytes[p+1]
                    if red { area += 1 }
                    if red && y == height - Int(patch.midY) { count += 1; firstX = min(firstX, col); lastX = max(lastX, col) }
                    if red != patch.contains(CGPoint(x: CGFloat(col) + 0.5, y: CGFloat(height - y) - 0.5)) { mismatches += 1 }
                    if bytes[p+3] != 255 { uncovered += 1 }
                }
            }
            XCTAssertEqual(uncovered, 0)
            XCTAssertGreaterThan(lastX - firstX + 1, 0)
            XCTAssertEqual(Double(area), Double(patch.width * patch.height), accuracy: 200)
            if x == 0 { XCTAssertEqual(mismatches, 0) } else {
                XCTAssertGreaterThan(mismatches, 0)
                XCTAssertLessThan(mismatches, width * height / 25)
            }
        }
    }

    func testMovieUsesNeutralPhotoAtStartAndEnd() async throws {
        let configuration = FloatingPhotoConfiguration(
            backgroundBlur: 0,
            backgroundBlurOpacity: 0,
            backgroundScale: 1,
            foregroundDepth: 1,
            backgroundDepth: 0,
            edgeFogOpacity: 0
        )
        let renderer = FloatingPhotoRenderer(
            source: photo,
            depth: depth,
            foregroundMask: mask,
            configuration: configuration
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await renderer.exportVideo(to: url, size: size, duration: 1, frameRate: 8)
        let asset = AVURLAsset(url: url)
        XCTAssertGreaterThan(asset.duration.seconds, 0.9)
        XCTAssertNotNil(try AVAssetImageGenerator(asset: asset).copyCGImage(at: .zero, actualTime: nil))
    }

    func testForegroundMaskKeepsBackgroundVerticesFlat() {
        let fullDepth = CIImage(color: .white).cropped(to: bounds)
        let surface = PhotoSurface(
            imageSize: size,
            depth: fullDepth,
            foregroundMask: mask,
            configuration: .default,
            context: FloatingPhotoRenderer.context
        )

        XCTAssertTrue(surface.hasDepth)
        XCTAssertTrue(surface.hasForegroundMask)
        XCTAssertEqual(surface.vertices.first?.z, 0)
        XCTAssertGreaterThan(surface.vertices.map(\.z).max() ?? 0, 0)
    }
}
