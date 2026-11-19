import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import UIKit

struct FloatingPhotoRenderer {
    let layers: FloatingPhotoLayers
    let configuration: FloatingPhotoConfiguration

    func render(
        at normalizedOffset: CGSize,
        canvasSize: CGSize
    ) -> CIImage {
        let offset = CGSize(
            width: max(-1, min(1, normalizedOffset.width)),
            height: max(-1, min(1, normalizedOffset.height))
        )
        let target = CGRect(origin: .zero, size: canvasSize)

        let background = layers.background
            .transformedToFill(target, additionalScale: configuration.backgroundScale)
            .transformed(by: CGAffineTransform(
                translationX: offset.width * configuration.backgroundDepth * canvasSize.width,
                y: -offset.height * configuration.backgroundDepth * canvasSize.height
            ))

        guard let foreground = layers.foreground else {
            return background.cropped(to: target)
        }

        let movedForeground = foreground
            .transformedToFill(target)
            .transformed(by: CGAffineTransform(
                translationX: offset.width * configuration.foregroundDepth * canvasSize.width,
                y: -offset.height * configuration.foregroundDepth * canvasSize.height
            ))

        return movedForeground.composited(over: background).cropped(to: target)
    }

    func exportVideo(
        to url: URL,
        size: CGSize,
        duration: TimeInterval,
        frameRate: Int32
    ) async throws {
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw FloatingPhotoError.exportFailed
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(size.width * size.height * 4),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )

        guard writer.canAdd(input) else { throw FloatingPhotoError.exportFailed }
        writer.add(input)
        guard writer.startWriting() else { throw FloatingPhotoError.exportFailed }
        writer.startSession(atSourceTime: .zero)

        let context = CIContext()
        let frameCount = Int((duration * Double(frameRate)).rounded(.up))
        let frameDuration = CMTime(value: 1, timescale: frameRate)

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            let progress = frameCount <= 1 ? 0 : Double(frame) / Double(frameCount - 1)
            let phase = progress < 0.5 ? progress * 2 : (1 - progress) * 2
            let angle = (phase * 2 - 1)
            let image = render(
                at: CGSize(
                    width: CGFloat(angle) * configuration.intensity,
                    height: CGFloat(sin(progress * .pi * 2)) * configuration.intensity
                ),
                canvasSize: size
            )

            guard let buffer = makePixelBuffer(size: size) else {
                input.markAsFinished()
                writer.cancelWriting()
                throw FloatingPhotoError.exportFailed
            }

            context.render(image, to: buffer)
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(frame))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                input.markAsFinished()
                writer.cancelWriting()
                throw FloatingPhotoError.exportFailed
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        guard writer.status == .completed else {
            throw writer.error ?? FloatingPhotoError.exportFailed
        }
    }

    private func makePixelBuffer(size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &buffer
        )
        return buffer
    }
}

private extension CIImage {
    func transformedToFill(_ target: CGRect, additionalScale: CGFloat = 1) -> CIImage {
        let scale = max(target.width / extent.width, target.height / extent.height) * additionalScale
        let scaled = transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = target.midX - scaled.extent.midX
        let y = target.midY - scaled.extent.midY
        return scaled.transformed(by: CGAffineTransform(translationX: x, y: y))
    }
}
