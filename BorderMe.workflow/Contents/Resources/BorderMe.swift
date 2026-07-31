import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum BorderMeError: LocalizedError {
    case usage
    case cannotRead
    case notAnImage
    case animatedImage
    case invalidDimensions
    case cannotRender
    case cannotWrite

    // These surface in a Finder dialog that already names the file, so they
    // stay short and leave the path out.
    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: borderme-engine <input> <output> <border: small|medium|large> <preset>"
        case .cannotRead:
            return "the file could not be opened"
        case .notAnImage:
            return "not a readable image file"
        case .animatedImage:
            return "animated and multi-page images are not supported"
        case .invalidDimensions:
            return "the image has invalid pixel dimensions"
        case .cannotRender:
            return "the image could not be rendered"
        case .cannotWrite:
            return "the bordered copy could not be written"
        }
    }
}

private enum BorderSize: String {
    case small
    case medium
    case large

    var fraction: Double {
        switch self {
        case .small: return 0.02
        case .medium: return 0.05
        case .large: return 0.08
        }
    }
}

private enum OutputPreset: String {
    case small
    case medium
    case large
    case instagramPortrait = "instagram-portrait"
    case instagramLandscape = "instagram-landscape"

    var jpegQuality: Double {
        switch self {
        case .small: return 0.75
        case .medium: return 0.85
        case .large: return 0.92
        case .instagramPortrait, .instagramLandscape: return 0.92
        }
    }

    var maximumStandardEdge: Int? {
        switch self {
        case .small: return 1_200
        case .medium: return 2_400
        case .large, .instagramPortrait, .instagramLandscape: return nil
        }
    }

    var instagramCanvas: (width: Int, height: Int)? {
        switch self {
        case .instagramPortrait: return (1_080, 1_440)
        case .instagramLandscape: return (1_080, 566)
        case .small, .medium, .large: return nil
        }
    }
}

private struct RenderPlan {
    let canvasWidth: Int
    let canvasHeight: Int
    let imageWidth: Int
    let imageHeight: Int

    var imageOriginX: Int { (canvasWidth - imageWidth) / 2 }
    var imageOriginY: Int { (canvasHeight - imageHeight) / 2 }
}

private func integerProperty(_ properties: [CFString: Any], key: CFString) -> Int? {
    if let number = properties[key] as? NSNumber {
        return number.intValue
    }
    return properties[key] as? Int
}

private func orientedDimensions(from source: CGImageSource) throws -> (width: Int, height: Int) {
    guard
        let rawProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let rawWidth = integerProperty(rawProperties, key: kCGImagePropertyPixelWidth),
        let rawHeight = integerProperty(rawProperties, key: kCGImagePropertyPixelHeight),
        rawWidth > 0,
        rawHeight > 0
    else {
        throw BorderMeError.invalidDimensions
    }

    let orientation = integerProperty(rawProperties, key: kCGImagePropertyOrientation) ?? 1
    if (5...8).contains(orientation) {
        return (rawHeight, rawWidth)
    }
    return (rawWidth, rawHeight)
}

/// The border is split evenly across opposite edges, so a canvas that differs
/// from the image by an odd number of pixels would leave one edge a pixel
/// wider than the other. Growing the canvas to match the image's parity keeps
/// every border symmetric.
private func matchingParity(canvas: Int, image: Int) -> Int {
    return (canvas - image) % 2 == 0 ? canvas : canvas + 1
}

private func standardPlan(
    width: Int,
    height: Int,
    border: BorderSize,
    maximumEdge: Int?
) -> RenderPlan {
    let unscaledBorder = max(1, Int((Double(min(width, height)) * border.fraction).rounded()))
    let unscaledCanvasWidth = width + (2 * unscaledBorder)
    let unscaledCanvasHeight = height + (2 * unscaledBorder)

    var scale = 1.0
    if let maximumEdge {
        let longestEdge = max(unscaledCanvasWidth, unscaledCanvasHeight)
        if longestEdge > maximumEdge {
            scale = Double(maximumEdge) / Double(longestEdge)
        }
    }

    let imageWidth = max(1, Int((Double(width) * scale).rounded()))
    let imageHeight = max(1, Int((Double(height) * scale).rounded()))
    let canvasWidth = max(imageWidth, Int((Double(unscaledCanvasWidth) * scale).rounded()))
    let canvasHeight = max(imageHeight, Int((Double(unscaledCanvasHeight) * scale).rounded()))

    return RenderPlan(
        canvasWidth: matchingParity(canvas: canvasWidth, image: imageWidth),
        canvasHeight: matchingParity(canvas: canvasHeight, image: imageHeight),
        imageWidth: imageWidth,
        imageHeight: imageHeight
    )
}

private func instagramPlan(
    width: Int,
    height: Int,
    border: BorderSize,
    canvas: (width: Int, height: Int)
) -> RenderPlan {
    let margin = max(1, Int((Double(min(canvas.width, canvas.height)) * border.fraction).rounded()))
    let availableWidth = max(1, canvas.width - (2 * margin))
    let availableHeight = max(1, canvas.height - (2 * margin))

    let widthScale = Double(availableWidth) / Double(width)
    let heightScale = Double(availableHeight) / Double(height)
    let scale = min(1.0, widthScale, heightScale)
    var imageWidth = min(max(1, Int((Double(width) * scale).rounded(.down))), availableWidth)
    var imageHeight = min(max(1, Int((Double(height) * scale).rounded(.down))), availableHeight)

    // The canvas is a fixed size here, so symmetry comes from trimming the
    // image by a pixel rather than growing the canvas.
    if (canvas.width - imageWidth) % 2 != 0 { imageWidth = max(1, imageWidth - 1) }
    if (canvas.height - imageHeight) % 2 != 0 { imageHeight = max(1, imageHeight - 1) }

    return RenderPlan(
        canvasWidth: canvas.width,
        canvasHeight: canvas.height,
        imageWidth: imageWidth,
        imageHeight: imageHeight
    )
}

private func normalizedImage(from source: CGImageSource, maximumPixelSize: Int) throws -> CGImage {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        kCGImageSourceShouldCacheImmediately: true
    ]

    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        throw BorderMeError.cannotRender
    }
    return image
}

/// Instagram assumes sRGB, so anything bound for it is converted. Everything
/// else keeps the original's RGB profile — converting a wide-gamut photo to
/// sRGB would quietly clip its most saturated colours.
private func destinationColorSpace(for image: CGImage, preset: OutputPreset) throws -> CGColorSpace {
    guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw BorderMeError.cannotRender
    }
    guard preset.instagramCanvas == nil else {
        return sRGB
    }
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

private func render(source: CGImageSource, plan: RenderPlan, preset: OutputPreset) throws -> CGImage {
    let image = try normalizedImage(
        from: source,
        maximumPixelSize: max(plan.imageWidth, plan.imageHeight)
    )
    let colorSpace = try destinationColorSpace(for: image, preset: preset)

    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    guard
        let context = CGContext(
            data: nil,
            width: plan.canvasWidth,
            height: plan.canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ),
        let white = CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1])
    else {
        throw BorderMeError.cannotRender
    }

    context.setFillColor(white)
    context.fill(CGRect(x: 0, y: 0, width: plan.canvasWidth, height: plan.canvasHeight))
    context.interpolationQuality = .high

    let destination = CGRect(
        x: plan.imageOriginX,
        y: plan.imageOriginY,
        width: plan.imageWidth,
        height: plan.imageHeight
    )
    context.draw(image, in: destination)

    guard let rendered = context.makeImage() else {
        throw BorderMeError.cannotRender
    }
    return rendered
}

/// Authorship and capture metadata is carried across so the bordered copy is
/// still attributable. Location is deliberately left behind: these files are
/// made to be posted, and GPS coordinates are rarely something you meant to
/// publish along with them.
private func preservedMetadata(from source: CGImageSource) -> [CFString: Any] {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
        return [:]
    }

    let carried: [CFString] = [
        kCGImagePropertyTIFFDictionary,
        kCGImagePropertyExifDictionary,
        kCGImagePropertyExifAuxDictionary,
        kCGImagePropertyIPTCDictionary
    ]
    // The pixels have already been rotated and resized, so any dimension or
    // orientation the original recorded would now be a lie.
    let stale: [CFString] = [
        kCGImagePropertyTIFFOrientation,
        kCGImagePropertyExifPixelXDimension,
        kCGImagePropertyExifPixelYDimension,
        kCGImagePropertyExifColorSpace
    ]

    var preserved: [CFString: Any] = [:]
    for key in carried {
        guard var dictionary = properties[key] as? [CFString: Any] else { continue }
        for staleKey in stale {
            dictionary.removeValue(forKey: staleKey)
        }
        if !dictionary.isEmpty {
            preserved[key] = dictionary
        }
    }
    return preserved
}

private func writeJPEG(
    _ image: CGImage,
    to outputURL: URL,
    quality: Double,
    metadata: [CFString: Any]
) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    ) else {
        throw BorderMeError.cannotWrite
    }

    var properties = metadata
    properties[kCGImageDestinationLossyCompressionQuality] = quality
    properties[kCGImagePropertyOrientation] = 1

    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw BorderMeError.cannotWrite
    }
}

private func run() throws {
    let arguments = CommandLine.arguments
    guard
        arguments.count == 5,
        let border = BorderSize(rawValue: arguments[3]),
        let preset = OutputPreset(rawValue: arguments[4])
    else {
        throw BorderMeError.usage
    }

    let inputURL = URL(fileURLWithPath: arguments[1])
    let outputURL = URL(fileURLWithPath: arguments[2])
    guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil) else {
        throw BorderMeError.cannotRead
    }

    // An empty or corrupt file still produces an image source, it just has no
    // images in it. That is a different failure from a multi-frame animation.
    let frameCount = CGImageSourceGetCount(source)
    guard frameCount > 0 else {
        throw BorderMeError.notAnImage
    }
    guard frameCount == 1 else {
        throw BorderMeError.animatedImage
    }

    let dimensions = try orientedDimensions(from: source)
    let plan: RenderPlan
    if let canvas = preset.instagramCanvas {
        plan = instagramPlan(
            width: dimensions.width,
            height: dimensions.height,
            border: border,
            canvas: canvas
        )
    } else {
        plan = standardPlan(
            width: dimensions.width,
            height: dimensions.height,
            border: border,
            maximumEdge: preset.maximumStandardEdge
        )
    }

    let image = try render(source: source, plan: plan, preset: preset)
    try writeJPEG(
        image,
        to: outputURL,
        quality: preset.jpegQuality,
        metadata: preservedMetadata(from: source)
    )
}

do {
    try run()
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
