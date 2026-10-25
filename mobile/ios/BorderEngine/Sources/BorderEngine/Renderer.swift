import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct RenderedImage: Sendable {
    public let jpegData: Data
    public let width: Int
    public let height: Int
}

public enum BorderEngineError: Error, Equatable, Sendable {
    case cannotRead
    case notAnImage
    case animatedImage
    case invalidDimensions
    case cannotRender
    case cannotEncode

    /// Shown beside the photo's number, so it stays short.
    public var reason: String {
        switch self {
        case .cannotRead: return "the file could not be opened"
        case .notAnImage: return "not a readable image file"
        case .animatedImage: return "animated and multi-page images are not supported"
        case .invalidDimensions: return "the image has invalid pixel dimensions"
        case .cannotRender: return "the image could not be rendered"
        case .cannotEncode: return "the bordered copy could not be written"
        }
    }
}

public enum Renderer {
    public static let jpegQuality = 0.92
    static let previewQuality = 0.8

    /// The full bordered photo, with authorship metadata carried across.
    public static func render(sourceURL: URL, settings: RenderSettings, maximumEdge: Int) throws -> RenderedImage {
        let source = try openSource(sourceURL)
        let size = try orientedDimensions(of: source)
        let plan = RenderPlanner.plan(
            sourceWidth: size.width, sourceHeight: size.height,
            border: settings.border, preset: settings.size, maximumEdge: maximumEdge
        )
        let image = try draw(source: source, plan: plan, outputScale: 1, settings: settings)
        let data = try encodeJPEG(image, quality: jpegQuality, metadata: preservedMetadata(from: source))
        return RenderedImage(jpegData: data, width: image.width, height: image.height)
    }

    /// A small render with exactly the full render's proportions, for showing
    /// on screen. It carries no metadata because it is never saved.
    public static func preview(sourceURL: URL, settings: RenderSettings, maximumEdge: Int) throws -> RenderedImage {
        let source = try openSource(sourceURL)
        let size = try orientedDimensions(of: source)
        let plan = RenderPlanner.plan(
            sourceWidth: size.width, sourceHeight: size.height,
            border: settings.border, preset: settings.size, maximumEdge: EngineLimits.appMaximumEdge
        )
        let scale = min(1.0, Double(maximumEdge) / Double(max(plan.canvasWidth, plan.canvasHeight)))
        let image = try draw(source: source, plan: plan, outputScale: scale, settings: settings)
        let data = try encodeJPEG(image, quality: previewQuality, metadata: [:])
        return RenderedImage(jpegData: data, width: image.width, height: image.height)
    }

    static func openSource(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw BorderEngineError.cannotRead
        }
        // An empty or corrupt file still produces an image source, it just has
        // no images in it. That is a different failure from an animation.
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw BorderEngineError.notAnImage }
        guard frameCount == 1 else { throw BorderEngineError.animatedImage }
        return source
    }

    private static func integerProperty(_ properties: [CFString: Any], key: CFString) -> Int? {
        if let number = properties[key] as? NSNumber { return number.intValue }
        return properties[key] as? Int
    }

    static func orientedDimensions(of source: CGImageSource) throws -> (width: Int, height: Int) {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let rawWidth = integerProperty(properties, key: kCGImagePropertyPixelWidth),
            let rawHeight = integerProperty(properties, key: kCGImagePropertyPixelHeight),
            rawWidth > 0,
            rawHeight > 0
        else {
            throw BorderEngineError.invalidDimensions
        }
        let orientation = integerProperty(properties, key: kCGImagePropertyOrientation) ?? 1
        return (5...8).contains(orientation) ? (rawHeight, rawWidth) : (rawWidth, rawHeight)
    }

    private static func decodedImage(from source: CGImageSource, maximumPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw BorderEngineError.cannotRender
        }
        return image
    }

    private static func colorSpace(for image: CGImage, size: SizePreset) throws -> CGColorSpace {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { throw BorderEngineError.cannotRender }
        guard !size.convertsToSRGB else { return sRGB }
        guard
            let space = image.colorSpace,
            space.model == .rgb,
            space.numberOfComponents == 3,
            space.supportsOutput
        else {
            return sRGB
        }
        return space
    }

    private static func draw(source: CGImageSource, plan: RenderPlan, outputScale: Double, settings: RenderSettings) throws -> CGImage {
        let canvasWidth = max(1, Int((Double(plan.canvasWidth) * outputScale).rounded()))
        let canvasHeight = max(1, Int((Double(plan.canvasHeight) * outputScale).rounded()))
        let imageRect = CGRect(
            x: Double(plan.imageOriginX) * outputScale,
            y: Double(plan.imageOriginY) * outputScale,
            width: Double(plan.imageWidth) * outputScale,
            height: Double(plan.imageHeight) * outputScale
        )

        let decodeEdge = max(1, Int(max(imageRect.width, imageRect.height).rounded(.up)))
        let image = try decodedImage(from: source, maximumPixelSize: decodeEdge)
        let space = try colorSpace(for: image, size: settings.size)
        let rgb = settings.colour.rgb

        guard
            let context = CGContext(
                data: nil, width: canvasWidth, height: canvasHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ),
            let fill = CGColor(colorSpace: space, components: [rgb.red, rgb.green, rgb.blue, 1])
        else {
            throw BorderEngineError.cannotRender
        }

        context.setFillColor(fill)
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.interpolationQuality = .high
        context.draw(image, in: imageRect)

        guard let rendered = context.makeImage() else { throw BorderEngineError.cannotRender }
        return rendered
    }

    /// Authorship and capture metadata is carried across so the bordered copy
    /// is still attributable. Location is deliberately left behind: these
    /// files are made to be posted.
    private static func preservedMetadata(from source: CGImageSource) -> [CFString: Any] {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return [:]
        }
        let carried: [CFString] = [
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyExifDictionary,
            kCGImagePropertyExifAuxDictionary,
            kCGImagePropertyIPTCDictionary
        ]
        // The pixels have been rotated and resized, so any dimension or
        // orientation the original recorded would now be wrong.
        let stale: [CFString] = [
            kCGImagePropertyTIFFOrientation,
            kCGImagePropertyExifPixelXDimension,
            kCGImagePropertyExifPixelYDimension,
            kCGImagePropertyExifColorSpace
        ]
        var preserved: [CFString: Any] = [:]
        for key in carried {
            guard var dictionary = properties[key] as? [CFString: Any] else { continue }
            for staleKey in stale { dictionary.removeValue(forKey: staleKey) }
            if !dictionary.isEmpty { preserved[key] = dictionary }
        }
        return preserved
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double, metadata: [CFString: Any]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw BorderEngineError.cannotEncode
        }
        var properties = metadata
        properties[kCGImageDestinationLossyCompressionQuality] = quality
        properties[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw BorderEngineError.cannotEncode }
        return data as Data
    }
}
