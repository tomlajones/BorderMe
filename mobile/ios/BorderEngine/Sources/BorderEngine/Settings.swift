import Foundation

public enum BorderSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large

    /// Measured against the photo's shorter edge, as on the Mac.
    public var fraction: Double {
        switch self {
        case .small: return 0.02
        case .medium: return 0.05
        case .large: return 0.08
        }
    }

    public var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

public enum BorderColour: String, Codable, CaseIterable, Sendable {
    case white
    case offWhite = "off-white"
    case lightGrey = "light-grey"
    case black
    /// The colour the person picked, kept in `RenderSettings.customColour`.
    case custom

    /// Nil for custom, whose colour lives in the settings.
    public var presetRGB: RGB? {
        switch self {
        case .white: return RGB(red: 1, green: 1, blue: 1)
        case .offWhite: return RGB(red: 0.98, green: 0.97, blue: 0.94)
        case .lightGrey: return RGB(red: 0.90, green: 0.90, blue: 0.90)
        case .black: return RGB(red: 0, green: 0, blue: 0)
        case .custom: return nil
        }
    }

    public var label: String {
        switch self {
        case .white: return "White"
        case .offWhite: return "Off-white"
        case .lightGrey: return "Light grey"
        case .black: return "Black"
        case .custom: return "Custom"
        }
    }
}

public struct RGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Reads "#RRGGBB" (the # is optional). Anything else is nil.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }
}

/// The canvas shape. Shapes with an orientation are named long side first and
/// turned on their side for portrait, so 5:4 in portrait is Instagram's 4:5.
public enum Shape: String, Codable, CaseIterable, Sendable {
    case fiveFour = "5:4"
    case fourThree = "4:3"
    case threeTwo = "3:2"
    case sixteenNine = "16:9"
    case square = "1:1"
    case instagramWide = "1.91:1"
    case custom
    case original

    /// Long side by short side. 1.91:1 is written as 191:100 so the canvas
    /// lands on that ratio exactly.
    var landscapeRatio: (width: Int, height: Int)? {
        switch self {
        case .fiveFour: return (5, 4)
        case .fourThree: return (4, 3)
        case .threeTwo: return (3, 2)
        case .sixteenNine: return (16, 9)
        case .square: return (1, 1)
        case .instagramWide: return (191, 100)
        case .custom, .original: return nil
        }
    }

    /// Square has no sides to swap, and 1.91:1 only exists as a landscape
    /// Instagram shape. A custom ratio is typed in the way round it's wanted.
    public var hasOrientation: Bool {
        switch self {
        case .fiveFour, .fourThree, .threeTwo, .sixteenNine: return true
        case .square, .instagramWide, .custom, .original: return false
        }
    }
}

public enum Orientation: String, Codable, CaseIterable, Sendable {
    case portrait
    case landscape
}

/// Turns a typed ratio such as 2.35 : 1 into whole numbers. Canvases grow in
/// steps of one ratio unit, so large terms would mean coarse steps and extra
/// border; terms above 100 are swapped for the nearest ratio that fits, which
/// is within a fraction of a percent.
public enum CustomRatio {
    /// Wider or taller than this would make a sliver of a canvas.
    public static let maximumAspect = 3.0

    public static func wholeNumbers(width: Double, height: Double) -> (width: Int, height: Int) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return (4, 5) }
        let aspect = width / height
        // Typed values carry up to two decimal places, so hundredths make
        // them whole.
        var w = Int((width * 100).rounded())
        var h = Int((height * 100).rounded())
        if w <= 0 || h <= 0 || aspect > maximumAspect || aspect < 1 / maximumAspect {
            let clamped = min(max(aspect, 1 / maximumAspect), maximumAspect)
            w = Int((clamped * 1000).rounded())
            h = 1000
        }
        let divisor = gcd(w, h)
        w /= divisor
        h /= divisor
        if max(w, h) <= 100 { return (w, h) }
        let target = Double(w) / Double(h)
        var best = (width: 1, height: 1)
        var bestError = Double.infinity
        for candidateHeight in 1...100 {
            let candidateWidth = Int((Double(candidateHeight) * target).rounded())
            guard (1...100).contains(candidateWidth) else { continue }
            let error = abs(Double(candidateWidth) / Double(candidateHeight) - target)
            if error < bestError - 1e-12 {
                best = (candidateWidth, candidateHeight)
                bestError = error
            }
        }
        return best
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}

public struct RenderSettings: Codable, Equatable, Sendable {
    public var border: BorderSize
    public var colour: BorderColour
    public var shape: Shape
    public var orientation: Orientation
    /// "#RRGGBB", used when `colour` is custom.
    public var customColour: String
    public var customWidth: Double
    public var customHeight: Double

    public static let defaultCustomColour = "#F4F1EA"

    public init(
        border: BorderSize,
        colour: BorderColour,
        shape: Shape,
        orientation: Orientation = .portrait,
        customColour: String = RenderSettings.defaultCustomColour,
        customWidth: Double = 7,
        customHeight: Double = 5
    ) {
        self.border = border
        self.colour = colour
        self.shape = shape
        self.orientation = orientation
        self.customColour = customColour
        self.customWidth = customWidth
        self.customHeight = customHeight
    }

    public static let standard = RenderSettings(border: .medium, colour: .white, shape: .fiveFour)

    /// The exact canvas ratio as width by height, or nil to keep the photo's
    /// own shape.
    public var ratio: (width: Int, height: Int)? {
        switch shape {
        case .original:
            return nil
        case .custom:
            return CustomRatio.wholeNumbers(width: customWidth, height: customHeight)
        default:
            guard let landscape = shape.landscapeRatio else { return nil }
            if shape.hasOrientation && orientation == .portrait {
                return (landscape.height, landscape.width)
            }
            return landscape
        }
    }

    /// The border fill. A custom colour that doesn't parse falls back to the
    /// default custom colour rather than failing the render.
    public var fillRGB: RGB {
        colour.presetRGB
            ?? RGB(hex: customColour)
            ?? RGB(hex: RenderSettings.defaultCustomColour)!
    }

    /// Instagram assumes sRGB. Original keeps a wide-gamut photo's colours.
    public var convertsToSRGB: Bool { shape != .original }

    /// Reads the map Dart sends. Anything missing or unknown falls back to the
    /// standard settings rather than failing the request.
    public init(channelValue: Any?) {
        let map = channelValue as? [String: Any]
        let standard = RenderSettings.standard
        border = (map?["border"] as? String).flatMap(BorderSize.init(rawValue:)) ?? standard.border
        colour = (map?["colour"] as? String).flatMap(BorderColour.init(rawValue:)) ?? standard.colour
        shape = (map?["shape"] as? String).flatMap(Shape.init(rawValue:)) ?? standard.shape
        orientation = (map?["orientation"] as? String).flatMap(Orientation.init(rawValue:)) ?? standard.orientation
        customColour = (map?["customColour"] as? String).flatMap { RGB(hex: $0) == nil ? nil : $0 }
            ?? standard.customColour
        customWidth = (map?["customWidth"] as? NSNumber)?.doubleValue ?? standard.customWidth
        customHeight = (map?["customHeight"] as? NSNumber)?.doubleValue ?? standard.customHeight
    }

    public var channelValue: [String: Any] {
        [
            "border": border.rawValue,
            "colour": colour.rawValue,
            "shape": shape.rawValue,
            "orientation": orientation.rawValue,
            "customColour": customColour,
            "customWidth": customWidth,
            "customHeight": customHeight
        ]
    }

}

public enum EngineLimits {
    /// Far beyond anything Instagram displays, and it keeps the render buffer
    /// for a very large photo to a few hundred megabytes.
    public static let appMaximumEdge = 8_192
    /// Share extensions get roughly 120 MB of memory, so they render smaller.
    /// Measured on the Mac with the block-by-block decode, a render at this cap
    /// peaks near 40-60 MB for 12-48 MP HEIC and baseline JPEG photos and
    /// 60-70 MB for progressive JPEGs. Formats decoded whole (PNG, TIFF and
    /// the like) still peak near 90-125 MB for photos of that size.
    public static let extensionMaximumEdge = 3_072
    /// Instagram displays posts 1080 px wide, so a narrower canvas would only
    /// be upscaled by Instagram itself.
    public static let minimumRatioCanvasWidth = 1_080
}
