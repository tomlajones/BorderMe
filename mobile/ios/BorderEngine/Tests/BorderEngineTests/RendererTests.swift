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
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:23 12:00:00"],
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCCopyrightNotice: "Copyright Tom Jones",
                kCGImagePropertyIPTCCity: "London",
                kCGImagePropertyIPTCProvinceState: "England",
                kCGImagePropertyIPTCCountryPrimaryLocationName: "United Kingdom",
                kCGImagePropertyIPTCCountryPrimaryLocationCode: "GBR",
                kCGImagePropertyIPTCSubLocation: "Hampstead Heath",
                kCGImagePropertyIPTCContentLocationName: "Parliament Hill",
                kCGImagePropertyIPTCContentLocationCode: "GBR"
            ]
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
        let iptc = try XCTUnwrap(output[kCGImagePropertyIPTCDictionary] as? [CFString: Any])
        XCTAssertEqual(iptc[kCGImagePropertyIPTCCopyrightNotice] as? String, "Copyright Tom Jones")
        for name in [
            kCGImagePropertyIPTCCity, kCGImagePropertyIPTCProvinceState,
            kCGImagePropertyIPTCCountryPrimaryLocationName, kCGImagePropertyIPTCCountryPrimaryLocationCode,
            kCGImagePropertyIPTCSubLocation, kCGImagePropertyIPTCContentLocationName,
            kCGImagePropertyIPTCContentLocationCode
        ] {
            XCTAssertNil(iptc[name], "\(name)")
        }
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

    /// Each EXIF orientation must come out the way ImageIO itself turns the
    /// photo upright, for both of the formats the renderer decodes in blocks.
    func testEveryOrientationComesOutUpright() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        // A different colour in each quadrant, so any turn or mirror shows.
        let quadrants: [(CGRect, [CGFloat])] = [
            (CGRect(x: 0, y: 200, width: 300, height: 200), [0.9, 0.1, 0.1, 1]),
            (CGRect(x: 300, y: 200, width: 300, height: 200), [0.1, 0.8, 0.1, 1]),
            (CGRect(x: 0, y: 0, width: 300, height: 200), [0.1, 0.1, 0.9, 1]),
            (CGRect(x: 300, y: 0, width: 300, height: 200), [0.9, 0.9, 0.1, 1])
        ]
        for (rect, components) in quadrants {
            context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: components)))
            context.fill(rect)
        }
        let stored = try XCTUnwrap(context.makeImage())

        // The Share extension's cap takes the leaner, slower decode path.
        for cap in [EngineLimits.appMaximumEdge, EngineLimits.extensionMaximumEdge] {
        for type in [UTType.jpeg, UTType.heic] {
            for orientation in 1...8 {
                let url = directory.appendingPathComponent("o\(orientation).\(type.preferredFilenameExtension ?? "img")")
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
                    continue // No HEIF encoder on this machine.
                }
                CGImageDestinationAddImage(destination, stored, [kCGImagePropertyOrientation: orientation] as CFDictionary)
                XCTAssertTrue(CGImageDestinationFinalize(destination))

                let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
                let upright = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 600
                ] as CFDictionary))
                let expected = try pixels(of: try jpegData(upright))

                let settings = RenderSettings(border: .medium, colour: .white, size: .original)
                let rendered = try Renderer.render(sourceURL: url, settings: settings, maximumEdge: cap)
                let actual = try pixels(of: rendered.jpegData)
                let plan = RenderPlanner.plan(
                    sourceWidth: upright.width, sourceHeight: upright.height,
                    border: .medium, preset: .original, maximumEdge: cap
                )
                XCTAssertEqual(actual.width, plan.canvasWidth, "\(type) \(orientation)")
                XCTAssertEqual(actual.height, plan.canvasHeight, "\(type) \(orientation)")
                // The plan's origin counts up from the bottom; pixel rows count down.
                let photoTop = plan.canvasHeight - plan.imageOriginY - plan.imageHeight

                for (fx, fy) in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)] {
                    let e = (Int(fy * Double(expected.height)) * expected.width + Int(fx * Double(expected.width))) * 4
                    let ax = plan.imageOriginX + Int(fx * Double(plan.imageWidth))
                    let ay = photoTop + Int(fy * Double(plan.imageHeight))
                    let a = (ay * actual.width + ax) * 4
                    for channel in 0..<3 {
                        XCTAssertEqual(
                            Int(actual.bytes[a + channel]), Int(expected.bytes[e + channel]), accuracy: 24,
                            "\(type) orientation \(orientation) cap \(cap) at (\(fx), \(fy))"
                        )
                    }
                }
            }
        }
        }
    }

    /// The block-by-block draw must match a single-pass downscale: no seams,
    /// no misplaced blocks. 2400x1800 at a 1600 cap uses the compact blocks
    /// (three HEIF columns, eight rows) at a non-integer scale.
    func testBlocksJoinWithoutSeams() throws {
        let width = 2400, height = 1800
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        // Smooth, but changing fast enough that a block drawn a few pixels out
        // of place changes what lands there.
        let across = try XCTUnwrap(CGGradient(
            colorsSpace: space,
            colors: (0...16).map { CGColor(colorSpace: space, components: $0 % 2 == 0 ? [0.9, 0.2, 0.1, 1] : [0.1, 0.3, 0.9, 1])! } as CFArray,
            locations: (0...16).map { CGFloat($0) / 16 }
        ))
        context.drawLinearGradient(across, start: .zero, end: CGPoint(x: width, y: 0), options: [])
        let down = try XCTUnwrap(CGGradient(
            colorsSpace: space,
            colors: (0...18).map { CGColor(colorSpace: space, components: [0.2, 0.9, 0.3, $0 % 2 == 0 ? 0 : 0.85])! } as CFArray,
            locations: (0...18).map { CGFloat($0) / 18 }
        ))
        context.drawLinearGradient(down, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        let photo = try XCTUnwrap(context.makeImage())

        for type in [UTType.jpeg, UTType.heic] {
            let url = directory.appendingPathComponent("gradient.\(type.preferredFilenameExtension ?? "img")")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
                continue // No HEIF encoder on this machine.
            }
            CGImageDestinationAddImage(destination, photo, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))

            let settings = RenderSettings(border: .medium, colour: .white, size: .original)
            let rendered = try Renderer.render(sourceURL: url, settings: settings, maximumEdge: 1600)
            let actual = try pixels(of: rendered.jpegData)
            let plan = RenderPlanner.plan(sourceWidth: width, sourceHeight: height, border: .medium, preset: .original, maximumEdge: 1600)
            XCTAssertEqual(actual.width, plan.canvasWidth)

            // The reference: the whole photo decoded and drawn in one pass.
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let whole = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let single = try XCTUnwrap(CGContext(
                data: nil, width: plan.imageWidth, height: plan.imageHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            single.interpolationQuality = .high
            single.draw(whole, in: CGRect(x: 0, y: 0, width: plan.imageWidth, height: plan.imageHeight))
            let expected = try pixels(of: try jpegData(try XCTUnwrap(single.makeImage())))

            // Compare the photo, less a 2 px rim where it meets the border. Rows
            // and columns are averaged over 100 px stretches, so one block out
            // of place stands out however small it is.
            let photoTop = plan.canvasHeight - plan.imageOriginY - plan.imageHeight
            let columns = plan.imageWidth - 4, rows = plan.imageHeight - 4
            let stretch = 100
            var rowTotals = [Int](repeating: 0, count: rows * (columns / stretch + 1))
            var columnTotals = [Int](repeating: 0, count: columns * (rows / stretch + 1))
            var total = 0
            actual.bytes.withUnsafeBufferPointer { actualBytes in
                expected.bytes.withUnsafeBufferPointer { expectedBytes in
                    for y in 0..<rows {
                        for x in 0..<columns {
                            let a = ((photoTop + y + 2) * actual.width + plan.imageOriginX + x + 2) * 4
                            let e = ((y + 2) * expected.width + x + 2) * 4
                            let difference = abs(Int(actualBytes[a]) - Int(expectedBytes[e]))
                                + abs(Int(actualBytes[a + 1]) - Int(expectedBytes[e + 1]))
                                + abs(Int(actualBytes[a + 2]) - Int(expectedBytes[e + 2]))
                            rowTotals[y * (columns / stretch + 1) + x / stretch] += difference
                            columnTotals[x * (rows / stretch + 1) + y / stretch] += difference
                            total += difference
                        }
                    }
                }
            }
            func worst(_ totals: [Int], lines: Int, length: Int) -> (line: Int, mean: Double) {
                let perLine = length / stretch + 1
                var result = (line: 0, mean: 0.0)
                for (index, sum) in totals.enumerated() {
                    let count = min(stretch, length - (index % perLine) * stretch)
                    guard count >= stretch / 2 else { continue }
                    let mean = Double(sum) / Double(count * 3)
                    if mean > result.mean { result = (index / perLine, mean) }
                }
                return result
            }
            XCTAssertLessThan(Double(total) / Double(rows * columns * 3), 1.5, "\(type) overall")
            let worstRow = worst(rowTotals, lines: rows, length: columns)
            let worstColumn = worst(columnTotals, lines: columns, length: rows)
            XCTAssertLessThan(worstRow.mean, 3, "\(type) row \(worstRow.line)")
            XCTAssertLessThan(worstColumn.mean, 3, "\(type) column \(worstColumn.line)")
        }
    }

    private func jpegData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: Renderer.jpegQuality] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testRejectsFilesThatAreNotImages() throws {
        let url = directory.appendingPathComponent("notes.jpg")
        try Data("not a photo".utf8).write(to: url)
        XCTAssertThrowsError(try Renderer.render(sourceURL: url, settings: .standard, maximumEdge: 8192)) { error in
            XCTAssertEqual(error as? BorderEngineError, .notAnImage)
        }
    }
}
