import CoreImage
import simd

/// A connected grid in top-left photo coordinates. Each vertex owns one original texture coordinate.
struct PhotoSurface {
    let imageSize: CGSize
    let columns: Int
    let rows: Int
    let vertices: [SIMD4<Float>]
    let indices: [UInt16]
    let hasDepth: Bool
    let hasForegroundMask: Bool
    private let maximumGradient: Float

    init(
        imageSize: CGSize,
        depth: CIImage?,
        foregroundMask: CIImage? = nil,
        configuration: FloatingPhotoConfiguration,
        context: CIContext
    ) {
        let longSide = max(imageSize.width, imageSize.height)
        let columns = max(2, Int((128 * imageSize.width / longSide).rounded()))
        let rows = max(2, Int((128 * imageSize.height / longSide).rounded()))
        let depthSamples = depth.flatMap { Self.sample($0, columns: columns, rows: rows, configuration: configuration, context: context) }
        let maskSamples = foregroundMask.flatMap { Self.sample($0, columns: columns, rows: rows, configuration: configuration, context: context) }
        self.imageSize = imageSize
        self.columns = columns
        self.rows = rows
        hasDepth = depthSamples != nil
        hasForegroundMask = maskSamples != nil

        let shortSide = min(imageSize.width, imageSize.height)
        let width = Float(imageSize.width / shortSide), height = Float(imageSize.height / shortSide)
        let foreground = Float(min(2, max(0, configuration.foregroundDepth)))
        let background = Float(min(2, max(0, configuration.backgroundDepth)))
        var vertices = [SIMD4<Float>]()
        vertices.reserveCapacity((columns + 1) * (rows + 1))
        for y in 0...rows {
            for x in 0...columns {
                let u = Float(x) / Float(columns), v = Float(y) / Float(rows)
                let distanceToEdge = min(min(u, 1 - u) * width, min(v, 1 - v) * height)
                let t = min(1, distanceToEdge / 0.09)
                let edgeWeight = t * t * (3 - 2 * t)
                let index = y * (columns + 1) + x
                let disparity: Float
                if let maskSamples {
                    let subjectDepth = depthSamples?[index] ?? maskSamples[index]
                    disparity = subjectDepth * maskSamples[index] * foreground
                } else {
                    disparity = depthSamples.map { $0[index] * (foreground + background) - background } ?? (-0.35 * background)
                }
                vertices.append(SIMD4(u, v, disparity * edgeWeight, 0))
            }
        }
        self.vertices = vertices

        var indices = [UInt16]()
        indices.reserveCapacity(6 * columns * rows)
        var steepest: Float = 0
        let dx = Float(columns) / width, dy = Float(rows) / height
        for y in 0..<rows {
            for x in 0..<columns {
                let a = y * (columns + 1) + x, b = a + 1, c = a + columns + 1, d = c + 1
                indices.append(contentsOf: [UInt16(a), UInt16(b), UInt16(c), UInt16(b), UInt16(d), UInt16(c)])
                let za = vertices[a].z, zb = vertices[b].z, zc = vertices[c].z, zd = vertices[d].z
                steepest = max(steepest, hypot((zb - za) * dx, (zc - za) * dy), hypot((zd - zc) * dx, (zd - zb) * dy))
            }
        }
        self.indices = indices
        maximumGradient = steepest
    }

    private static func sample(_ field: CIImage, columns: Int, rows: Int, configuration: FloatingPhotoConfiguration, context: CIContext) -> [Float]? {
        let bounds = field.extent
        guard !bounds.isEmpty, !bounds.isInfinite else { return nil }
        let sx = CGFloat(columns) / bounds.width, sy = CGFloat(rows) / bounds.height
        let grid = field.clampedToExtent().transformed(by: CGAffineTransform(
            a: sx, b: 0, c: 0, d: sy, tx: 0.5 - bounds.minX * sx, ty: 0.5 - bounds.minY * sy
        ))
        let softness = min(1, max(0, configuration.backgroundBlur / 12)) * min(1, max(0, configuration.backgroundBlurOpacity))
        let radius = max(1, CGFloat(min(columns, rows)) * (0.016 + 0.025 * softness))
        let smoothedDepth = grid.applyingGaussianBlur(sigma: Double(radius))
        let count = (columns + 1) * (rows + 1)
        var values = [Float](repeating: 0, count: count)
        context.render(smoothedDepth, toBitmap: &values, rowBytes: (columns + 1) * MemoryLayout<Float>.stride,
                       bounds: CGRect(x: 0, y: 0, width: columns + 1, height: rows + 1), format: .Rf, colorSpace: nil)
        let sorted = values.filter(\.isFinite).sorted()
        guard sorted.count == count else { return nil }
        let low = sorted[count / 100], high = sorted[count - 1 - count / 100]
        guard high - low > max(0.0001, abs(high) * 0.003) else { return nil }
        return values.map { min(1, max(0, ($0 - low) / (high - low))) }
    }

    /// xy aspect-fills the viewport. zw is unit disparity's travel in clip coordinates.
    func camera(at offset: CGSize, canvas: CGSize, configuration: FloatingPhotoConfiguration) -> SIMD4<Float> {
        let fit = max(canvas.width / imageSize.width, canvas.height / imageSize.height) * max(1, configuration.backgroundScale)
        let displayed = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)
        var direction = SIMD2(Float(offset.width), Float(offset.height))
        if !direction.x.isFinite || !direction.y.isFinite { direction = .zero }
        let magnitude = simd_length(direction)
        let travelFraction = min(1, max(0, magnitude))
        if magnitude > 0, magnitude.isFinite {
            direction /= magnitude
        } else {
            direction = .zero
        }
        let requested = 0.035 * min(1, max(0, configuration.intensity)) * min(canvas.width, canvas.height)
        // For every triangle, det(I + travel ⊗ grad(disparity)) stays positive at every allowed tilt.
        let foldLimit = maximumGradient > 0 ? 0.65 * min(displayed.width, displayed.height) / CGFloat(maximumGradient) : requested
        let travel = 2 * min(requested, foldLimit) * CGFloat(travelFraction)
        return SIMD4(Float(displayed.width / canvas.width), Float(displayed.height / canvas.height),
                     direction.x * Float(travel / canvas.width), direction.y * Float(travel / canvas.height))
    }
}
