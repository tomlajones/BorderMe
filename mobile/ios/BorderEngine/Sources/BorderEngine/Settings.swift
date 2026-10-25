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

    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .white: return (1, 1, 1)
        case .offWhite: return (0.98, 0.97, 0.94)
        case .lightGrey: return (0.90, 0.90, 0.90)
        case .black: return (0, 0, 0)
        }
    }

    public var label: String {
        switch self {
        case .white: return "White"
        case .offWhite: return "Off-white"
        case .lightGrey: return "Light grey"
        case .black: return "Black"
        }
    }
}

public enum SizePreset: String, Codable, CaseIterable, Sendable {
    case instagramPortrait = "instagram-portrait"
    case instagramTall = "instagram-tall"
    case instagramLandscape = "instagram-landscape"
    case square
    case original

    /// An exact aspect ratio, or nil to keep the photo's own shape. 1.91:1 is
    /// written as 191:100 so the canvas lands on that ratio exactly.
    public var ratio: (width: Int, height: Int)? {
        switch self {
        case .instagramPortrait: return (4, 5)
        case .instagramTall: return (3, 4)
        case .instagramLandscape: return (191, 100)
        case .square: return (1, 1)
        case .original: return nil
        }
    }

    /// Instagram assumes sRGB. Original keeps a wide-gamut photo's colours.
    public var convertsToSRGB: Bool { self != .original }

    public var shortLabel: String {
        switch self {
        case .instagramPortrait: return "4:5"
        case .instagramTall: return "3:4"
        case .instagramLandscape: return "1.91:1"
        case .square: return "1:1"
        case .original: return "Original"
        }
    }
}

public struct RenderSettings: Codable, Equatable, Sendable {
    public var border: BorderSize
    public var colour: BorderColour
    public var size: SizePreset

    public init(border: BorderSize, colour: BorderColour, size: SizePreset) {
        self.border = border
        self.colour = colour
        self.size = size
    }

    public static let standard = RenderSettings(border: .medium, colour: .white, size: .instagramPortrait)

    /// Reads the map Dart sends. Anything missing or unknown falls back to the
    /// standard settings rather than failing the request.
    public init(channelValue: Any?) {
        let map = channelValue as? [String: Any]
        let standard = RenderSettings.standard
        border = (map?["border"] as? String).flatMap(BorderSize.init(rawValue:)) ?? standard.border
        colour = (map?["colour"] as? String).flatMap(BorderColour.init(rawValue:)) ?? standard.colour
        size = (map?["size"] as? String).flatMap(SizePreset.init(rawValue:)) ?? standard.size
    }

    public var channelValue: [String: String] {
        ["border": border.rawValue, "colour": colour.rawValue, "size": size.rawValue]
    }
}

public enum EngineLimits {
    /// Far beyond anything Instagram displays, and it keeps the render buffer
    /// for a very large photo to a few hundred megabytes.
    public static let appMaximumEdge = 8_192
    /// Share extensions get roughly 120 MB of memory, so they render smaller.
    /// Measured on the Mac with the block-by-block decode, a render at this cap
    /// peaks near 40-60 MB for 12-48 MP JPEG and HEIC photos.
    public static let extensionMaximumEdge = 3_072
    /// Instagram displays posts 1080 px wide, so a narrower canvas would only
    /// be upscaled by Instagram itself.
    public static let minimumRatioCanvasWidth = 1_080
}
