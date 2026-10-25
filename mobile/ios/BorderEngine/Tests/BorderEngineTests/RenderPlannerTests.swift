import XCTest
@testable import BorderEngine

final class RenderPlannerTests: XCTestCase {
    private func plan(
        _ width: Int,
        _ height: Int,
        _ preset: SizePreset,
        border: BorderSize = .medium,
        cap: Int = EngineLimits.appMaximumEdge
    ) -> RenderPlan {
        RenderPlanner.plan(sourceWidth: width, sourceHeight: height, border: border, preset: preset, maximumEdge: cap)
    }

    private func canvas(_ width: Int, _ height: Int, _ preset: SizePreset) -> String {
        let result = plan(width, height, preset)
        return "\(result.canvasWidth)x\(result.canvasHeight)"
    }

    /// These sizes came from the Mac engine on 2026-10-23, so the phone and the
    /// Mac must produce identical canvases for the same photo.
    func testMatchesMacEngineReferenceSizes() {
        let cases: [(Int, Int, SizePreset, String)] = [
            (4000, 6000, .instagramPortrait, "5120x6400"),
            (6000, 4000, .instagramPortrait, "6400x8000"),
            (6016, 6016, .instagramPortrait, "6556x8195"),
            (5000, 4000, .instagramPortrait, "5400x6750"),
            (700, 1000, .instagramPortrait, "1080x1350"),
            (9000, 12000, .instagramPortrait, "6560x8200"),
            (4000, 6000, .instagramTall, "4800x6400"),
            (6000, 4000, .instagramTall, "6144x8192"),
            (6016, 6016, .instagramTall, "6147x8196"),
            (5000, 4000, .instagramTall, "5400x7200"),
            (700, 1000, .instagramTall, "1080x1440"),
            (9000, 12000, .instagramTall, "6147x8196"),
            (4000, 6000, .instagramLandscape, "8404x4400"),
            (6000, 4000, .instagramLandscape, "8404x4400"),
            (6016, 6016, .instagramLandscape, "8213x4300"),
            (5000, 4000, .instagramLandscape, "8213x4300"),
            (700, 1000, .instagramLandscape, "2292x1200"),
            (9000, 12000, .instagramLandscape, "8404x4400"),
            (4000, 6000, .original, "4400x6400")
        ]
        for (width, height, preset, expected) in cases {
            XCTAssertEqual(canvas(width, height, preset), expected, "\(width)x\(height) \(preset.rawValue)")
        }
    }

    func testPortraitKeepsPhotoAtNativeSizeAndCentresIt() {
        let result = plan(4000, 6000, .instagramPortrait)
        XCTAssertEqual(result.imageWidth, 4000)
        XCTAssertEqual(result.imageHeight, 6000)
        XCTAssertEqual(result.imageOriginX, 560)
        XCTAssertEqual(result.imageOriginY, 200)
    }

    func testRatioPresetsAreExactEvenAndNeverUpscale() {
        let sizes = [(700, 1000), (1080, 1080), (3024, 4032), (4032, 3024), (4000, 6000), (6000, 4000), (8064, 6048), (1234, 5678)]
        let presets: [SizePreset] = [.instagramPortrait, .instagramTall, .instagramLandscape, .square]
        for preset in presets {
            let ratio = preset.ratio!
            for border in BorderSize.allCases {
                for (width, height) in sizes {
                    let label = "\(width)x\(height) \(preset.rawValue) \(border.rawValue)"
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

    func testExtensionCapKeepsCanvasNearFourK() {
        for preset in SizePreset.allCases {
            let result = plan(8064, 6048, preset, cap: EngineLimits.extensionMaximumEdge)
            let longEdge = max(result.canvasWidth, result.canvasHeight)
            // Rounding up to an exact ratio can add up to two ratio steps.
            let slack = 2 * max(preset.ratio?.width ?? 1, preset.ratio?.height ?? 1)
            XCTAssertLessThanOrEqual(longEdge, EngineLimits.extensionMaximumEdge + slack, preset.rawValue)
            XCTAssertGreaterThan(longEdge, EngineLimits.extensionMaximumEdge / 2, preset.rawValue)
        }
    }

    func testOriginalAddsEvenBorderAndScalesOnlyPastTheCap() {
        let small = plan(4000, 6000, .original)
        XCTAssertEqual(small.imageWidth, 4000)
        XCTAssertEqual(small.imageOriginX, 200)
        XCTAssertEqual(small.imageOriginY, 200)

        let huge = plan(9000, 12000, .original)
        XCTAssertEqual(max(huge.canvasWidth, huge.canvasHeight), EngineLimits.appMaximumEdge)
        XCTAssertLessThan(huge.imageWidth, 9000)
        XCTAssertEqual((huge.canvasWidth - huge.imageWidth) % 2, 0)
        XCTAssertEqual((huge.canvasHeight - huge.imageHeight) % 2, 0)
    }

    func testSettingsRoundTripThroughChannelValues() {
        let settings = RenderSettings(border: .large, colour: .offWhite, size: .square)
        XCTAssertEqual(settings.channelValue, ["border": "large", "colour": "off-white", "size": "square"])
        XCTAssertEqual(RenderSettings(channelValue: settings.channelValue), settings)
        XCTAssertEqual(RenderSettings(channelValue: nil), .standard)
        XCTAssertEqual(RenderSettings(channelValue: ["border": "huge"]), .standard)
    }

    func testWireValuesMatchDart() {
        XCTAssertEqual(BorderSize.allCases.map(\.rawValue), ["small", "medium", "large"])
        XCTAssertEqual(BorderColour.allCases.map(\.rawValue), ["white", "off-white", "light-grey", "black"])
        XCTAssertEqual(
            SizePreset.allCases.map(\.rawValue),
            ["instagram-portrait", "instagram-tall", "instagram-landscape", "square", "original"]
        )
    }
}
