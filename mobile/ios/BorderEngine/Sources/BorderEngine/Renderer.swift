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
        // Only the Share extension's cap needs the slower, leaner decode.
        let compact = maximumEdge <= EngineLimits.extensionMaximumEdge
        let image = try draw(sourceURL: sourceURL, source: source, plan: plan, outputScale: 1, settings: settings, compact: compact)
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
        let image = try draw(sourceURL: sourceURL, source: source, plan: plan, outputScale: scale, settings: settings, compact: false)
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
        let stored = try storedDimensions(of: source)
        return (5...8).contains(orientation(of: source)) ? (stored.height, stored.width) : stored
    }

    private static func storedDimensions(of source: CGImageSource) throws -> (width: Int, height: Int) {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = integerProperty(properties, key: kCGImagePropertyPixelWidth),
            let height = integerProperty(properties, key: kCGImagePropertyPixelHeight),
            width > 0,
            height > 0
        else {
            throw BorderEngineError.invalidDimensions
        }
        return (width, height)
    }

    private static func orientation(of source: CGImageSource) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return properties.flatMap { integerProperty($0, key: kCGImagePropertyOrientation) } ?? 1
    }

    /// Decoding a large photo whole costs several times the canvas it is
    /// drawn into (the decoder's working buffers, the decoded photo, then a
    /// colour-converted copy while drawing), which is more than a Share
    /// extension is allowed. So the photo is decoded and drawn into the canvas
    /// a block at a time, and only one block's pixels exist at once.
    private struct BlockSource {
        /// Stored pixel size, before `orientation` is applied.
        let width: Int
        let height: Int
        let colorSpace: CGColorSpace?
        let orientation: Int
        let blockWidth: Int
        let blockHeight: Int
        /// The stored pixels in `rect`, top-left origin.
        let block: (CGRect) -> CGImage?
    }

    /// `compact` trades speed for memory: smaller HEIF blocks mean more
    /// decoder start-ups but a lower peak.
    private static func blockSource(sourceURL: URL, source: CGImageSource, minimumLongEdge: Int, compact: Bool) throws -> BlockSource {
        let type = CGImageSourceGetType(source) as String?
        let decodesInBlocks = type == UTType.jpeg.identifier || type == UTType.heic.identifier || type == UTType.heif.identifier
        guard decodesInBlocks else {
            // Other formats are rare here and their decoders may not decode a
            // region on its own, so they are decoded once, already rotated and
            // at the size they are drawn, and only colour-converted in blocks.
            let image = try decodedImage(from: source, maximumPixelSize: minimumLongEdge)
            return BlockSource(
                width: image.width, height: image.height, colorSpace: image.colorSpace, orientation: 1,
                blockWidth: image.width, blockHeight: 256, block: { image.cropping(to: $0) }
            )
        }

        // JPEG and HEIF decoders can shrink by a power of two as they decode;
        // take the largest reduction that still leaves enough pixels.
        let size = try storedDimensions(of: source)
        let longEdge = max(size.width, size.height)
        let factor = [8, 4, 2].first { longEdge / $0 >= minimumLongEdge } ?? 1
        let options = [kCGImageSourceSubsampleFactor: factor, kCGImageSourceShouldCache: false] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { throw BorderEngineError.cannotRender }
        let orientation = orientation(of: source)

        if type == UTType.jpeg.identifier {
            // A JPEG decodes top to bottom, so it is drawn in full-width bands.
            return BlockSource(
                width: image.width, height: image.height, colorSpace: image.colorSpace, orientation: orientation,
                blockWidth: image.width, blockHeight: 256, block: { image.cropping(to: $0) }
            )
        }
        // A HEIF image source holds on to what it has decoded until it is
        // released, which adds back up to the whole photo, so each block is
        // decoded from a source of its own.
        return BlockSource(
            width: image.width, height: image.height, colorSpace: image.colorSpace, orientation: orientation,
            blockWidth: compact ? 1024 : image.width, blockHeight: compact ? 256 : 512,
            block: { rect in
                guard
                    let blockSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                    let blockImage = CGImageSourceCreateImageAtIndex(blockSource, 0, options)
                else { return nil }
                return blockImage.cropping(to: rect)
            }
        )
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

    /// Maps the stored image, drawn at (0, 0, width, height), onto the upright
    /// photo its EXIF orientation describes, in Core Graphics' y-up space.
    private static func orientationTransform(_ orientation: Int, width: Double, height: Double) -> CGAffineTransform {
        switch orientation {
        case 2: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)
        case 3: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
        case 4: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
        case 5: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: height, ty: width)
        case 6: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
        case 7: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case 8: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        default: return .identity
        }
    }

    /// Draws the photo upright into `rect` one block at a time. Each block is
    /// decoded with a few pixels of its neighbours, so resampling at its edges
    /// sees the real photo rather than a hard edge, then clipped to its own
    /// pixels; with antialiasing off every canvas pixel is painted by exactly
    /// one block, so no seams show.
    private static func drawInBlocks(_ pixels: BlockSource, in rect: CGRect, context: CGContext) throws {
        let width = pixels.width
        let height = pixels.height
        let rotated = (5...8).contains(pixels.orientation)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / Double(rotated ? height : width), y: rect.height / Double(rotated ? width : height))
        context.concatenate(orientationTransform(pixels.orientation, width: Double(width), height: Double(height)))
        context.setShouldAntialias(false)

        let overlap = 8
        for top in stride(from: 0, to: height, by: pixels.blockHeight) {
            let bottom = min(height, top + pixels.blockHeight)
            let decodeTop = max(0, top - overlap)
            let decodeBottom = min(height, bottom + overlap)
            for left in stride(from: 0, to: width, by: pixels.blockWidth) {
                let right = min(width, left + pixels.blockWidth)
                let decodeLeft = max(0, left - overlap)
                let decodeRight = min(width, right + overlap)
                let drawn: Bool = autoreleasepool {
                    let decodeRect = CGRect(x: decodeLeft, y: decodeTop, width: decodeRight - decodeLeft, height: decodeBottom - decodeTop)
                    guard let block = pixels.block(decodeRect) else { return false }
                    // Stored rows count down from the top; Core Graphics counts up.
                    context.saveGState()
                    context.clip(to: CGRect(x: left, y: height - bottom, width: right - left, height: bottom - top))
                    context.draw(block, in: CGRect(x: decodeLeft, y: height - decodeBottom, width: decodeRight - decodeLeft, height: decodeBottom - decodeTop))
                    context.restoreGState()
                    return true
                }
                guard drawn else { throw BorderEngineError.cannotRender }
            }
        }
    }

    private static func colorSpace(for photoSpace: CGColorSpace?, size: SizePreset) throws -> CGColorSpace {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { throw BorderEngineError.cannotRender }
        guard !size.convertsToSRGB else { return sRGB }
        guard
            let space = photoSpace,
            space.model == .rgb,
            space.numberOfComponents == 3,
            space.supportsOutput
        else {
            return sRGB
        }
        return space
    }

    private static func draw(
        sourceURL: URL, source: CGImageSource, plan: RenderPlan, outputScale: Double, settings: RenderSettings, compact: Bool
    ) throws -> CGImage {
        let canvasWidth = max(1, Int((Double(plan.canvasWidth) * outputScale).rounded()))
        let canvasHeight = max(1, Int((Double(plan.canvasHeight) * outputScale).rounded()))
        let imageRect = CGRect(
            x: Double(plan.imageOriginX) * outputScale,
            y: Double(plan.imageOriginY) * outputScale,
            width: Double(plan.imageWidth) * outputScale,
            height: Double(plan.imageHeight) * outputScale
        )

        let decodeEdge = max(1, Int(max(imageRect.width, imageRect.height).rounded(.up)))
        let pixels = try blockSource(sourceURL: sourceURL, source: source, minimumLongEdge: decodeEdge, compact: compact)
        let space = try colorSpace(for: pixels.colorSpace, size: settings.size)
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
        try drawInBlocks(pixels, in: imageRect, context: context)

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
