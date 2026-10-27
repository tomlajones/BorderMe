import XCTest
@testable import BorderEngine

private typealias Ratio = (width: Int, height: Int)?
private let instagramPortrait: Ratio = (4, 5)
private let instagramTall: Ratio = (3, 4)
private let instagramLandscape: Ratio = (191, 100)
private let square: Ratio = (1, 1)
private let original: Ratio = nil

final class RenderPlannerTests: XCTestCase {
    private func plan(
        _ width: Int,
        _ height: Int,
        _ preset: Ratio,
        border: BorderSize = .medium,
        cap: Int = EngineLimits.appMaximumEdge
    ) -> RenderPlan {
        RenderPlanner.plan(sourceWidth: width, sourceHeight: height, border: border, ratio: preset, maximumEdge: cap)
    }

    private func canvas(_ width: Int, _ height: Int, _ preset: Ratio) -> String {
        let result = plan(width, height, preset)
        return "\(result.canvasWidth)x\(result.canvasHeight)"
    }

    /// These sizes came from the Mac engine on 2026-10-23, so the phone and the
    /// Mac must produce identical canvases for the same photo.
    func testMatchesMacEngineReferenceSizes() {
        let cases: [(Int, Int, Ratio, String)] = [
            (4000, 6000, instagramPortrait, "5120x6400"),
            (6000, 4000, instagramPortrait, "6400x8000"),
            (6016, 6016, instagramPortrait, "6556x8195"),
            (5000, 4000, instagramPortrait, "5400x6750"),
            (700, 1000, instagramPortrait, "1080x1350"),
            (9000, 12000, instagramPortrait, "6560x8200"),
            (4000, 6000, instagramTall, "4800x6400"),
            (6000, 4000, instagramTall, "6144x8192"),
            (6016, 6016, instagramTall, "6147x8196"),
            (5000, 4000, instagramTall, "5400x7200"),
            (700, 1000, instagramTall, "1080x1440"),
            (9000, 12000, instagramTall, "6147x8196"),
            (4000, 6000, instagramLandscape, "8404x4400"),
            (6000, 4000, instagramLandscape, "8404x4400"),
            (6016, 6016, instagramLandscape, "8213x4300"),
            (5000, 4000, instagramLandscape, "8213x4300"),
            (700, 1000, instagramLandscape, "2292x1200"),
            (9000, 12000, instagramLandscape, "8404x4400"),
            (4000, 6000, original, "4400x6400")
        ]
        for (width, height, preset, expected) in cases {
            XCTAssertEqual(canvas(width, height, preset), expected, "\(width)x\(height) \(String(describing: preset))")
        }
    }

    func testPortraitKeepsPhotoAtNativeSizeAndCentresIt() {
        let result = plan(4000, 6000, instagramPortrait)
        XCTAssertEqual(result.imageWidth, 4000)
        XCTAssertEqual(result.imageHeight, 6000)
        XCTAssertEqual(result.imageOriginX, 560)
        XCTAssertEqual(result.imageOriginY, 200)
    }

    func testRatioPresetsAreExactEvenAndNeverUpscale() {
        let sizes = [(700, 1000), (1080, 1080), (3024, 4032), (4032, 3024), (4000, 6000), (6000, 4000), (8064, 6048), (1234, 5678)]
        let presets: [Ratio] = [instagramPortrait, instagramTall, instagramLandscape, square]
        for preset in presets {
            let ratio = preset!
            for border in BorderSize.allCases {
                for (width, height) in sizes {
                    let label = "\(width)x\(height) \(String(describing: preset)) \(border.rawValue)"
                    let result = plan(width, height, preset, border: border)
                    XCTAssertEqual(result.canvasWidth * ratio.height, result.canvasHeight * ratio.width, "ratio \(label)")
                    XCTAssertLessThanOrEqual(result.imageWidth, width, "upscaled \(label)")
                    XCTAssertLessThanOrEqual(result.imageHeight, height, "upscaled \(label)")
                    XCTAssertEqual((result.canvasWidth - result.imageWidth) % 2, 0, "uneven sides \(label)")
                    XCTAssertEqual((result.canvasHeight - result.imageHeight) % 2, 0, "uneven top/bottom \(label)")
                    XCTAssertGreaterThan(result.imageOriginX, 0, "no side border \(label)")
                    XCTAssertGreaterThan(result.imageOriginY, 0, "no top border \(label)")
                    XCTAssertGreaterThanOrEqual(result.canvasWidth, EngineLimits.minimumRatioCanvasWidth, "too narrow \(label)")
                }
            }
        }
    }

    func testExtensionCapKeepsCanvasNearThreeK() {
        var everyShape: [RenderSettings] = []
        for shape in Shape.allCases {
            for orientation in Orientation.allCases {
                everyShape.append(RenderSettings(border: .medium, colour: .white, shape: shape, orientation: orientation))
            }
        }
        everyShape.append(RenderSettings(border: .medium, colour: .white, shape: .custom, customWidth: 1, customHeight: 3))
        for settings in everyShape {
            let label = "\(settings.shape.rawValue) \(settings.orientation.rawValue)"
            let result = plan(8064, 6048, settings.ratio, cap: EngineLimits.extensionMaximumEdge)
            let longEdge = max(result.canvasWidth, result.canvasHeight)
            // Rounding up to an exact ratio can add up to two ratio steps, and
            // a 1:3 canvas is held at least 1080 px wide.
            let slack = max(2 * max(settings.ratio?.width ?? 1, settings.ratio?.height ?? 1), 1080 * 3 - EngineLimits.extensionMaximumEdge)
            XCTAssertLessThanOrEqual(longEdge, EngineLimits.extensionMaximumEdge + slack, label)
            XCTAssertGreaterThan(longEdge, EngineLimits.extensionMaximumEdge / 2, label)
        }
    }

    func testOriginalAddsEvenBorderAndScalesOnlyPastTheCap() {
        let small = plan(4000, 6000, original)
        XCTAssertEqual(small.imageWidth, 4000)
        XCTAssertEqual(small.imageOriginX, 200)
        XCTAssertEqual(small.imageOriginY, 200)

        let huge = plan(9000, 12000, original)
        XCTAssertEqual(max(huge.canvasWidth, huge.canvasHeight), EngineLimits.appMaximumEdge)
        XCTAssertLessThan(huge.imageWidth, 9000)
        XCTAssertEqual((huge.canvasWidth - huge.imageWidth) % 2, 0)
        XCTAssertEqual((huge.canvasHeight - huge.imageHeight) % 2, 0)
    }

    func testShapesTurnForOrientation() {
        func ratio(_ shape: Shape, _ orientation: Orientation) -> String {
            let r = RenderSettings(border: .medium, colour: .white, shape: shape, orientation: orientation).ratio
            return r.map { "\($0.width):\($0.height)" } ?? "none"
        }
        XCTAssertEqual(ratio(.fiveFour, .portrait), "4:5")
        XCTAssertEqual(ratio(.fiveFour, .landscape), "5:4")
        XCTAssertEqual(ratio(.fourThree, .portrait), "3:4")
        XCTAssertEqual(ratio(.threeTwo, .portrait), "2:3")
        XCTAssertEqual(ratio(.threeTwo, .landscape), "3:2")
        XCTAssertEqual(ratio(.sixteenNine, .portrait), "9:16")
        XCTAssertEqual(ratio(.square, .landscape), "1:1")
        XCTAssertEqual(ratio(.instagramWide, .portrait), "191:100")
        XCTAssertEqual(ratio(.original, .portrait), "none")
        XCTAssertEqual(RenderSettings.standard.ratio?.width, 4)
        XCTAssertEqual(RenderSettings.standard.ratio?.height, 5)
    }

    func testCustomRatiosBecomeSmallWholeNumbers() {
        func whole(_ w: Double, _ h: Double) -> String {
            let r = CustomRatio.wholeNumbers(width: w, height: h)
            return "\(r.width):\(r.height)"
        }
        XCTAssertEqual(whole(7, 5), "7:5")
        XCTAssertEqual(whole(2.35, 1), "47:20")
        XCTAssertEqual(whole(16, 10), "8:5")
        XCTAssertEqual(whole(10, 1), "3:1")
        XCTAssertEqual(whole(1, 10), "1:3")
        XCTAssertEqual(whole(0, 5), "4:5")
        // 9.7:7.3 is 97:73 already; 47.3:21.1 needs approximating under 100.
        XCTAssertEqual(whole(9.7, 7.3), "97:73")
        let approximate = CustomRatio.wholeNumbers(width: 47.3, height: 21.1)
        XCTAssertLessThanOrEqual(max(approximate.width, approximate.height), 100)
        XCTAssertEqual(Double(approximate.width) / Double(approximate.height), 47.3 / 21.1, accuracy: 0.005)
    }

    func testHexColoursParseAndFallBack() {
        XCTAssertEqual(RGB(hex: "#336699"), RGB(red: 0.2, green: 0.4, blue: 0.6))
        XCTAssertEqual(RGB(hex: "336699"), RGB(red: 0.2, green: 0.4, blue: 0.6))
        XCTAssertNil(RGB(hex: "#3366"))
        XCTAssertNil(RGB(hex: "#GGGGGG"))
        var settings = RenderSettings(border: .medium, colour: .custom, shape: .square, customColour: "#000000")
        XCTAssertEqual(settings.fillRGB, RGB(red: 0, green: 0, blue: 0))
        settings.customColour = "nonsense"
        XCTAssertEqual(settings.fillRGB, RGB(hex: RenderSettings.defaultCustomColour))
        settings.colour = .black
        XCTAssertEqual(settings.fillRGB, RGB(red: 0, green: 0, blue: 0))
    }

    func testSettingsRoundTripThroughChannelValues() {
        let settings = RenderSettings(
            border: .large, colour: .custom, shape: .custom, orientation: .landscape,
            customColour: "#336699", customWidth: 2.35, customHeight: 1
        )
        XCTAssertEqual(settings.channelValue["shape"] as? String, "custom")
        XCTAssertEqual(settings.channelValue["customColour"] as? String, "#336699")
        XCTAssertEqual(RenderSettings(channelValue: settings.channelValue), settings)
        XCTAssertEqual(RenderSettings(channelValue: nil), .standard)
        XCTAssertEqual(RenderSettings(channelValue: ["border": "huge"]), .standard)
        // Dart may send whole numbers as ints.
        let fromInts = RenderSettings(channelValue: ["shape": "custom", "customWidth": 7, "customHeight": 5])
        XCTAssertEqual(fromInts.customWidth, 7)
        XCTAssertEqual(RenderSettings(channelValue: ["customColour": "blue"]).customColour, RenderSettings.defaultCustomColour)
    }

    func testSettingsSurviveTheSharedStore() throws {
        let settings = RenderSettings(border: .small, colour: .custom, shape: .threeTwo, orientation: .landscape, customColour: "#112233")
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(RenderSettings.self, from: data), settings)
    }

    func testWireValuesMatchDart() {
        XCTAssertEqual(BorderSize.allCases.map(\.rawValue), ["small", "medium", "large"])
        XCTAssertEqual(BorderColour.allCases.map(\.rawValue), ["white", "off-white", "light-grey", "black", "custom"])
        XCTAssertEqual(
            Shape.allCases.map(\.rawValue),
            ["5:4", "4:3", "3:2", "16:9", "1:1", "1.91:1", "custom", "original"]
        )
        XCTAssertEqual(Orientation.allCases.map(\.rawValue), ["portrait", "landscape"])
    }
}
