import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum BorderMeError: LocalizedError {
    case usage
    case cannotRead(String)
    case animatedImage
    case invalidDimensions
    case cannotRender
    case cannotWrite(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: borderme-engine <input> <output> <border: small|medium|large> <preset>"
        case .cannotRead(let path):
            return "Cannot read image: \(path)"
        case .animatedImage:
            return "Animated or multi-page images are not supported"
        case .invalidDimensions:
            return "The image has invalid pixel dimensions"
        case .cannotRender:
            return "The image could not be rendered"
        case .cannotWrite(let path):
            return "Cannot write output: \(path)"
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

    let canvasWidth = max(1, Int((Double(unscaledCanvasWidth) * scale).rounded()))
    let canvasHeight = max(1, Int((Double(unscaledCanvasHeight) * scale).rounded()))
    let imageWidth = max(1, Int((Double(width) * scale).rounded()))
    let imageHeight = max(1, Int((Double(height) * scale).rounded()))

    return RenderPlan(
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        imageWidth: min(imageWidth, canvasWidth),
        imageHeight: min(imageHeight, canvasHeight)
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
    let imageWidth = max(1, Int((Double(width) * scale).rounded(.down)))
    let imageHeight = max(1, Int((Double(height) * scale).rounded(.down)))

    return RenderPlan(
        canvasWidth: canvas.width,
        canvasHeight: canvas.height,
        imageWidth: min(imageWidth, availableWidth),
        imageHeight: min(imageHeight, availableHeight)
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

private func render(source: CGImageSource, plan: RenderPlan) throws -> CGImage {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw BorderMeError.cannotRender
    }

    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    guard let context = CGContext(
        data: nil,
        width: plan.canvasWidth,
        height: plan.canvasHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        throw BorderMeError.cannotRender
    }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: plan.canvasWidth, height: plan.canvasHeight))
    context.interpolationQuality = .high

    let image = try normalizedImage(
        from: source,
        maximumPixelSize: max(plan.imageWidth, plan.imageHeight)
    )
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

private func writeJPEG(_ image: CGImage, to outputURL: URL, quality: Double) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    ) else {
        throw BorderMeError.cannotWrite(outputURL.path)
    }

    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: quality
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw BorderMeError.cannotWrite(outputURL.path)
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
        throw BorderMeError.cannotRead(inputURL.path)
    }
    guard CGImageSourceGetCount(source) == 1 else {
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

    let image = try render(source: source, plan: plan)
    try writeJPEG(image, to: outputURL, quality: preset.jpegQuality)
}

do {
    try run()
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
