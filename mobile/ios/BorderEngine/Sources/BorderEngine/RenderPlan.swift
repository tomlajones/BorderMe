import Foundation

public struct RenderPlan: Equatable, Sendable {
    public let canvasWidth: Int
    public let canvasHeight: Int
    public let imageWidth: Int
    public let imageHeight: Int

    public init(canvasWidth: Int, canvasHeight: Int, imageWidth: Int, imageHeight: Int) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    public var imageOriginX: Int { (canvasWidth - imageWidth) / 2 }
    public var imageOriginY: Int { (canvasHeight - imageHeight) / 2 }
}

/// Sizing maths ported unchanged from the Mac engine, so the same photo comes
/// out the same size on both.
public enum RenderPlanner {
    public static func plan(
        sourceWidth: Int,
        sourceHeight: Int,
        border: BorderSize,
        preset: SizePreset,
        maximumEdge: Int
    ) -> RenderPlan {
        if let ratio = preset.ratio {
            return ratioPlan(width: sourceWidth, height: sourceHeight, border: border, ratio: ratio, maximumEdge: maximumEdge)
        }
        return originalPlan(width: sourceWidth, height: sourceHeight, border: border, maximumEdge: maximumEdge)
    }

    /// The border is split evenly across opposite edges, so a canvas that
    /// differs from the image by an odd number of pixels would leave one edge a
    /// pixel wider than the other. Growing the canvas to match the image's
    /// parity keeps every border symmetric.
    private static func matchingParity(canvas: Int, image: Int) -> Int {
        (canvas - image) % 2 == 0 ? canvas : canvas + 1
    }

    private static func ceilingDivide(_ value: Int, _ divisor: Int) -> Int {
        (value + divisor - 1) / divisor
    }

    private static func originalPlan(width: Int, height: Int, border: BorderSize, maximumEdge: Int) -> RenderPlan {
        let unscaledBorder = max(1, Int((Double(min(width, height)) * border.fraction).rounded()))
        let unscaledCanvasWidth = width + (2 * unscaledBorder)
        let unscaledCanvasHeight = height + (2 * unscaledBorder)

        var scale = 1.0
        let longestEdge = max(unscaledCanvasWidth, unscaledCanvasHeight)
        if longestEdge > maximumEdge {
            scale = Double(maximumEdge) / Double(longestEdge)
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

    /// Builds the smallest exact-ratio canvas that holds the whole photo plus
    /// its border on every side. The photo is never cropped; whichever axis
    /// has spare room gets the extra border.
    private static func ratioPlan(
        width: Int,
        height: Int,
        border: BorderSize,
        ratio: (width: Int, height: Int),
        maximumEdge: Int
    ) -> RenderPlan {
        // Only a photo too large for the canvas cap is scaled, and only down.
        let margin = Double(min(width, height)) * border.fraction
        let longestRatioSide = Double(max(ratio.width, ratio.height))
        let fitWidth = Double(maximumEdge) * Double(ratio.width) / longestRatioSide
        let fitHeight = Double(maximumEdge) * Double(ratio.height) / longestRatioSide
        let scale = min(
            1.0,
            fitWidth / (Double(width) + 2 * margin),
            fitHeight / (Double(height) + 2 * margin)
        )

        var imageWidth = max(1, Int((Double(width) * scale).rounded(.down)))
        var imageHeight = max(1, Int((Double(height) * scale).rounded(.down)))
        let scaledMargin = max(1, Int((margin * scale).rounded()))

        // The canvas is ratio.width x ratio.height multiplied by a whole
        // number, which is what makes the ratio exact rather than approximate.
        var unit = max(
            ceilingDivide(imageWidth + 2 * scaledMargin, ratio.width),
            ceilingDivide(imageHeight + 2 * scaledMargin, ratio.height),
            ceilingDivide(EngineLimits.minimumRatioCanvasWidth, ratio.width)
        )

        // One step up in canvas size often fixes parity; anything left is
        // fixed by shrinking the image a pixel.
        func parityMismatches(_ candidate: Int) -> Int {
            let widthOff = (candidate * ratio.width - imageWidth) % 2 != 0 ? 1 : 0
            let heightOff = (candidate * ratio.height - imageHeight) % 2 != 0 ? 1 : 0
            return widthOff + heightOff
        }
        if parityMismatches(unit + 1) < parityMismatches(unit) {
            unit += 1
        }

        let canvasWidth = unit * ratio.width
        let canvasHeight = unit * ratio.height
        if (canvasWidth - imageWidth) % 2 != 0 { imageWidth = max(1, imageWidth - 1) }
        if (canvasHeight - imageHeight) % 2 != 0 { imageHeight = max(1, imageHeight - 1) }

        return RenderPlan(
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )
    }
}
