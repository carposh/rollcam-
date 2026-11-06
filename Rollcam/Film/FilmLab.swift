import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit

/// Turns a full-resolution original into a disposable-camera print.
enum FilmLab {
    struct Options {
        var dateStamp: Bool
        var capturedAt: Date
        var seed: UInt64
    }

    static let context = CIContext(options: [.cacheIntermediates: false])
    static let maxLongEdge: CGFloat = 3_000

    static func develop(_ original: Data, options: Options) -> Data? {
        guard var image = CIImage(data: original, options: [.applyOrientationProperty: true]) else { return nil }
        var rng = SeededGenerator(seed: options.seed)

        image = cropToViewfinder(image)
        image = downscale(image)
        let extent = CGRect(origin: .zero, size: CGSize(width: floor(image.extent.width), height: floor(image.extent.height)))
        image = image.cropped(to: extent)

        image = filmColour(image)
        if rng.nextDouble() < 0.3 { image = lightLeak(image, extent: extent, rng: &rng) }
        image = vignette(image, extent: extent)
        image = grain(image, extent: extent, rng: &rng).cropped(to: extent)

        guard let cg = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            return nil
        }
        var output = UIImage(cgImage: cg)
        if options.dateStamp { output = stamp(output, date: options.capturedAt) }
        return output.jpegData(compressionQuality: 0.9)
    }

    static func writeThumbnail(from imageURL: URL, to thumbURL: URL, maxPixel: Int = 480) {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else { return }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary),
              let data = UIImage(cgImage: thumb).jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: thumbURL, options: .atomic)
    }

    // MARK: - Steps

    /// The viewfinder is a 3:2 landscape window over the centre of the sensor; print exactly that.
    private static func cropToViewfinder(_ image: CIImage) -> CIImage {
        let e = image.extent
        let targetAspect: CGFloat = 3.0 / 2.0
        var crop = e
        if e.width / e.height > targetAspect {
            crop.size.width = e.height * targetAspect
            crop.origin.x = e.midX - crop.width / 2
        } else {
            crop.size.height = e.width / targetAspect
            crop.origin.y = e.midY - crop.height / 2
        }
        return image.cropped(to: crop.integral)
            .transformed(by: CGAffineTransform(translationX: -crop.integral.minX, y: -crop.integral.minY))
    }

    private static func downscale(_ image: CIImage) -> CIImage {
        let longEdge = max(image.extent.width, image.extent.height)
        guard longEdge > maxLongEdge else { return image }
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(maxLongEdge / longEdge)
        filter.aspectRatio = 1
        return filter.outputImage ?? image
    }

    /// Warm cast, slightly punchy saturation, lifted blacks and soft highlights.
    private static func filmColour(_ image: CIImage) -> CIImage {
        let warm = CIFilter.colorMatrix()
        warm.inputImage = image
        warm.rVector = CIVector(x: 1.06, y: 0.05, z: 0.00, w: 0)
        warm.gVector = CIVector(x: 0.02, y: 0.99, z: 0.01, w: 0)
        warm.bVector = CIVector(x: 0.00, y: 0.04, z: 0.84, w: 0)
        warm.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        warm.biasVector = CIVector(x: 0.025, y: 0.012, z: 0.0, w: 0)

        let controls = CIFilter.colorControls()
        controls.inputImage = warm.outputImage
        controls.saturation = 1.08
        controls.contrast = 1.04
        controls.brightness = 0.01

        let fade = CIFilter.toneCurve()
        fade.inputImage = controls.outputImage
        fade.point0 = CGPoint(x: 0.00, y: 0.07)
        fade.point1 = CGPoint(x: 0.25, y: 0.25)
        fade.point2 = CGPoint(x: 0.50, y: 0.52)
        fade.point3 = CGPoint(x: 0.75, y: 0.77)
        fade.point4 = CGPoint(x: 1.00, y: 0.95)
        return fade.outputImage ?? image
    }

    private static func vignette(_ image: CIImage, extent: CGRect) -> CIImage {
        let filter = CIFilter.vignetteEffect()
        filter.inputImage = image
        filter.center = CGPoint(x: extent.midX, y: extent.midY)
        filter.radius = Float(max(extent.width, extent.height) * 0.62)
        filter.intensity = 0.55
        return filter.outputImage?.cropped(to: extent) ?? image
    }

    /// An orange/red glow bleeding in from one edge, like light hitting the film.
    private static func lightLeak(_ image: CIImage, extent: CGRect, rng: inout SeededGenerator) -> CIImage {
        let fromLeft = rng.nextDouble() < 0.5
        let x = fromLeft ? extent.minX - extent.width * 0.05 : extent.maxX + extent.width * 0.05
        let y = extent.minY + extent.height * CGFloat(0.15 + rng.nextDouble() * 0.7)
        let reach = extent.width * CGFloat(0.35 + rng.nextDouble() * 0.35)

        func glow(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, alpha: CGFloat, radius: CGFloat, dy: CGFloat) -> CIImage? {
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: x, y: y + dy)
            gradient.radius0 = 0
            gradient.radius1 = Float(radius)
            gradient.color0 = CIColor(red: r, green: g, blue: b, alpha: alpha)
            gradient.color1 = CIColor(red: r, green: g, blue: b, alpha: 0)
            return gradient.outputImage?.cropped(to: extent)
        }

        var result = image
        let layers = [
            glow(1.0, 0.32, 0.08, alpha: 0.85, radius: reach, dy: 0),
            glow(1.0, 0.72, 0.25, alpha: 0.55, radius: reach * 0.55, dy: extent.height * 0.08),
        ]
        for case let layer? in layers {
            let screen = CIFilter.screenBlendMode()
            screen.inputImage = layer
            screen.backgroundImage = result
            result = screen.outputImage ?? result
        }
        return result
    }

    private static func grain(_ image: CIImage, extent: CGRect, rng: inout SeededGenerator) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        let offset = CGAffineTransform(translationX: CGFloat(rng.nextDouble() * 4_000), y: CGFloat(rng.nextDouble() * 4_000))
        let grainSize = max(1.0, max(extent.width, extent.height) / 2_000)

        // Monochrome noise centred on mid-grey, low amplitude, so soft-light only adds texture.
        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise.transformed(by: offset).transformed(by: CGAffineTransform(scaleX: grainSize, y: grainSize)).cropped(to: extent)
        let amount: CGFloat = 0.22
        let lane = CIVector(x: 0, y: amount, z: 0, w: 0)
        mono.rVector = lane
        mono.gVector = lane
        mono.bVector = lane
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mono.biasVector = CIVector(x: 0.5 - amount / 2, y: 0.5 - amount / 2, z: 0.5 - amount / 2, w: 1)

        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = mono.outputImage
        blend.backgroundImage = image
        return blend.outputImage ?? image
    }

    /// Orange LED-style date in the bottom-right corner, e.g. '26 11 6.
    private static func stamp(_ image: UIImage, date: Date) -> UIImage {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "''yy M d"
        let text = formatter.string(from: date)

        let size = image.size
        let fontSize = size.height * 0.045
        let orange = UIColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 0.95)
        let glow = NSShadow()
        glow.shadowColor = UIColor(red: 1.0, green: 0.35, blue: 0.0, alpha: 0.9)
        glow.shadowBlurRadius = fontSize * 0.35
        glow.shadowOffset = .zero
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: orange,
            .shadow: glow,
            .kern: fontSize * 0.08,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let margin = size.width * 0.045

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(at: .zero)
            (text as NSString).draw(
                at: CGPoint(x: size.width - margin - textSize.width, y: size.height - margin - textSize.height),
                withAttributes: attributes
            )
        }
    }
}

/// SplitMix64, so every frame gets its own repeatable grain and leak.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
