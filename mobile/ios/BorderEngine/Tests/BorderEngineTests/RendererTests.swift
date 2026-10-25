import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BorderEngine

final class RendererTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A solid red photo carrying location, copyright and capture date.
    private func makeFixture(width: Int, height: Int, colorSpace name: CFString = CGColorSpace.sRGB) throws -> URL {
        let space = try XCTUnwrap(CGColorSpace(name: name))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: [0.8, 0.2, 0.2, 1])))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let url = directory.appendingPathComponent("fixture-\(width)x\(height).jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W"
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFCopyright: "Copyright Tom Jones",
                kCGImagePropertyTIFFArtist: "Tom Jones"
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:23 12:00:00"]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    /// Decodes a JPEG into sRGB RGBA bytes, top row first.
    private func pixels(of data: Data) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (bytes, width, height)
    }

    private func isPhoto(_ bytes: [UInt8], _ offset: Int) -> Bool {
        bytes[offset] > 150 && bytes[offset + 1] < 110
    }

    private func matches(_ bytes: [UInt8], _ offset: Int, _ colour: BorderColour) -> Bool {
        let rgb = colour.rgb
        let expected = [rgb.red, rgb.green, rgb.blue].map { Int(($0 * 255).rounded()) }
        return (0..<3).allSatisfy { abs(Int(bytes[offset + $0]) - expected[$0]) <= 12 }
    }

    func testOutputDimensionsMatchThePlan() throws {
        let url = try makeFixture(width: 400, height: 600)
        for size in SizePreset.allCases {
            let settings = RenderSettings(border: .medium, colour: .white, size: size)
            let rendered = try Renderer.render(sourceURL: url, settings: settings, maximumEdge: EngineLimits.appMaximumEdge)
            let plan = RenderPlanner.plan(sourceWidth: 400, sourceHeight: 600, border: .medium, preset: size, maximumEdge: EngineLimits.appMaximumEdge)
            XCTAssertEqual(rendered.width, plan.canvasWidth, size.rawValue)
            XCTAssertEqual(rendered.height, plan.canvasHeight, size.rawValue)
            let decoded = try pixels(of: rendered.jpegData)
            XCTAssertEqual(decoded.width, plan.canvasWidth, size.rawValue)
            XCTAssertEqual(decoded.height, plan.canvasHeight, size.rawValue)
        }
    }

    func testBordersAreEvenAndUseTheChosenColour() throws {
        let url = try makeFixture(width: 400, height: 600)
        for colour in [BorderColour.white, .black, .lightGrey] {
            let settings = RenderSettings(border: .medium, colour: colour, size: .original)
            let rendered = try Renderer.render(sourceURL: url, settings: settings, maximumEdge: EngineLimits.appMaximumEdge)
            let (bytes, width, height) = try pixels(of: rendered.jpegData)
            XCTAssertTrue(matches(bytes, (2 * width + 2) * 4, colour), "corner \(colour.rawValue)")

            let middleRow = height / 2
            let left = (0..<width).first { isPhoto(bytes, (middleRow * width + $0) * 4) } ?? -1
            let right = (0..<width).first { isPhoto(bytes, (middleRow * width + (width - 1 - $0)) * 4) } ?? -1
            XCTAssertEqual(left, 20, accuracy: 1, "left border \(colour.rawValue)")
            XCTAssertEqual(right, 20, accuracy: 1, "right border \(colour.rawValue)")

            let middleColumn = width / 2
            let top = (0..<height).first { isPhoto(bytes, ($0 * width + middleColumn) * 4) } ?? -1
            let bottom = (0..<height).first { isPhoto(bytes, ((height - 1 - $0) * width + middleColumn) * 4) } ?? -1
            XCTAssertEqual(top, bottom, accuracy: 1, "top vs bottom \(colour.rawValue)")
        }
    }

    func testLocationIsRemovedAndAuthorshipKept() throws {
        let url = try makeFixture(width: 400, height: 600)
        let rendered = try Renderer.render(sourceURL: url, settings: .standard, maximumEdge: EngineLimits.appMaximumEdge)
        let output = try properties(of: rendered.jpegData)
        XCTAssertNil(output[kCGImagePropertyGPSDictionary])
        let tiff = try XCTUnwrap(output[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        XCTAssertEqual(tiff[kCGImagePropertyTIFFCopyright] as? String, "Copyright Tom Jones")
        let exif = try XCTUnwrap(output[kCGImagePropertyExifDictionary] as? [CFString: Any])
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal] as? String, "2026:10:23 12:00:00")
    }

    func testInstagramConvertsToSRGBAndOriginalKeepsDisplayP3() throws {
        let url = try makeFixture(width: 400, height: 600, colorSpace: CGColorSpace.displayP3)
        let instagram = try Renderer.render(sourceURL: url, settings: .standard, maximumEdge: EngineLimits.appMaximumEdge)
        let instagramProfile = try properties(of: instagram.jpegData)[kCGImagePropertyProfileName] as? String
        XCTAssertTrue(instagramProfile?.contains("sRGB") == true, instagramProfile ?? "no profile")

        let original = try Renderer.render(
            sourceURL: url,
            settings: RenderSettings(border: .medium, colour: .white, size: .original),
            maximumEdge: EngineLimits.appMaximumEdge
        )
        let originalProfile = try properties(of: original.jpegData)[kCGImagePropertyProfileName] as? String
        XCTAssertEqual(originalProfile, "Display P3")
    }

    func testPreviewIsSmallSameShapeAndCarriesNoMetadata() throws {
        let url = try makeFixture(width: 3000, height: 4000)
        let preview = try Renderer.preview(sourceURL: url, settings: .standard, maximumEdge: 300)
        XCTAssertLessThanOrEqual(max(preview.width, preview.height), 300)
        XCTAssertEqual(Double(preview.width) / Double(preview.height), 0.8, accuracy: 0.01)
        XCTAssertNil(try properties(of: preview.jpegData)[kCGImagePropertyGPSDictionary])
    }

    func testRejectsFilesThatAreNotImages() throws {
        let url = directory.appendingPathComponent("notes.jpg")
        try Data("not a photo".utf8).write(to: url)
        XCTAssertThrowsError(try Renderer.render(sourceURL: url, settings: .standard, maximumEdge: 8192)) { error in
            XCTAssertEqual(error as? BorderEngineError, .notAnImage)
        }
    }
}
