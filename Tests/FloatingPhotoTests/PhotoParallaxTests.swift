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

    func testExtremeTiltKeepsTheRenderedSubjectConnectedAndCoversTheCanvas() throws {
        let config = FloatingPhotoConfiguration(intensity: 12, backgroundScale: 1, foregroundDepth: 10, backgroundDepth: 10)
        let renderer = FloatingPhotoRenderer(source: photo, depth: depth, configuration: config)
        let device = try XCTUnwrap(renderer.device)
        for (width, height) in [(256, 176), (128, 242), (260, 88)] {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = .renderTarget
            let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            for (x, y) in [(1, 1), (-1, 1), (1, -1), (-1, -1), (100, 0)] {
                let commands = try XCTUnwrap(renderer.frame(at: CGSize(width: x, height: y), into: target))
                commands.commit()
                commands.waitUntilCompleted()
                XCTAssertEqual(commands.status, .completed)
                var pixels = [UInt8](repeating: 0, count: 4 * width * height)
                target.getBytes(&pixels, bytesPerRow: 4 * width, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
                XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 })
                try assertOneRedSubject(in: pixels, width: width, height: height)
            }
        }
    }

    // Flood-fill the visible subject. A curved silhouette can cross a single row more than once.
    private func assertOneRedSubject(in pixels: [UInt8], width: Int, height: Int) throws {
        let rowWidth = width + 2
        var red = [Bool](repeating: false, count: rowWidth * (height + 2))
        for y in 0..<height {
            for x in 0..<width {
                let i = 4 * (y * width + x)
                red[(y + 1) * rowWidth + x + 1] = pixels[i + 2] > pixels[i + 1]
            }
        }
        let seed = try XCTUnwrap(red.firstIndex(of: true))
        red[seed] = false
        var pending = [seed]
        while let pixel = pending.popLast() {
            for neighbor in [pixel - 1, pixel + 1, pixel - rowWidth, pixel + rowWidth] where red[neighbor] {
                red[neighbor] = false
                pending.append(neighbor)
            }
        }
        XCTAssertFalse(red.contains(true), "The subject should form a single connected region")
    }

    func testFlatDepthDegrades() {
        let surface = PhotoSurface(imageSize: size, depth: CIImage(color: .white).cropped(to: bounds), configuration: .default, context: FloatingPhotoRenderer.context)
        XCTAssertNil(surface.depthValues)
    }

    func testRenderedPhotoKeepsSubjectVisibleWithoutUncoveredPixels() throws {
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
            XCTAssertGreaterThan(Double(area), Double(patch.width * patch.height) * 0.7)
            if x == 0 {
                XCTAssertLessThan(mismatches, width * height / 40)
            } else {
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

    func testFlatDepthUsesTheForegroundMaskAsTheDepthTexture() throws {
        let flat = CIImage(color: .white).cropped(to: bounds)
        let surface = PhotoSurface(imageSize: size, depth: flat, foregroundMask: mask, configuration: .default, context: FloatingPhotoRenderer.context)
        let maskOnly = PhotoSurface(imageSize: size, depth: nil, foregroundMask: mask, configuration: .default, context: FloatingPhotoRenderer.context)
        let samples = try XCTUnwrap(surface.depthValues)
        XCTAssertEqual(samples, maskOnly.depthValues)
        XCTAssertEqual(samples.min(), 0)
        XCTAssertEqual(samples.max(), 1)
    }
}
