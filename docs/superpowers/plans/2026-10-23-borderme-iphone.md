# BorderMe for iPhone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A free iPhone app (Flutter UI and a native Swift image engine) plus a Share-sheet extension. It puts photos on a clean border at exact Instagram ratios or at original size, never cropped and never upscaled.

**Architecture:**
- Flutter (Dart) draws every screen and talks to native code over one `MethodChannel` and one `EventChannel`.
- All pixel work happens in Swift (CoreGraphics and ImageIO), ported from the Mac engine `BorderMe.workflow/Contents/Resources/BorderMe.swift`.
- The Swift engine lives in a Swift package (`mobile/ios/BorderEngine`), so its tests run on the Mac with `swift test`. The same source files are compiled directly into the Runner app target and the Share extension target.
- Photos reach native code as file paths: the native picker copies each picked file to a temporary folder. No image bytes cross the bridge except small previews.

**Tech Stack:**
- Flutter stable and Dart 3 (no pub packages beyond the Flutter SDK).
- Swift 5 language mode; CoreGraphics, ImageIO, Photos, PhotosUI, SwiftUI; XCTest.
- Homebrew Ruby with the `xcodeproj` gem, for scripted Xcode project edits.
- Xcode 27.1 with the iOS 27.1 SDK and simulators.

**Spec:** `docs/superpowers/specs/2026-10-23-borderme-iphone-design.md`

## Deviations from the spec (decided while planning)

1. **Bridge carries file paths, not Photos asset identifiers.** Fetching a `PHAsset` by identifier needs full library *read* permission, which contradicts the spec's add-only privacy decision. `PHPickerViewController` without a photo library hands back `NSItemProvider`s with no permission at all. The native side copies each original file (HEIC, JPEG, and so on, metadata intact) into a temporary folder and returns paths. Task 4 updates the spec's Bridge section to match.
2. **iCloud downloads show one "Loading photos…" screen** rather than per-thumbnail spinners. The picker's item providers download iCloud originals before handing them over, so the app knows nothing about a photo until it arrives. Photos that fail to load are counted and reported on the start screen.

## Global Constraints

- Bundle ID `com.tomlajones.borderme`; Share extension `com.tomlajones.borderme.share`; App Group `group.com.tomlajones.borderme`.
- Minimum iOS 16.0 for both targets. Swift language version 5.0 in Xcode targets; `swift-tools-version: 5.9` for the package.
- No third-party Dart or Swift dependencies. No network access, accounts, analytics or tracking.
- Channel names: `borderme/engine` (methods) and `borderme/engine/progress` (batch events).
- Wire values shared by Dart and Swift:
  - Border: `small`, `medium`, `large`.
  - Colour: `white`, `off-white`, `light-grey`, `black`.
  - Size: `instagram-portrait`, `instagram-tall`, `instagram-landscape`, `square`, `original`.
- Border fractions: Small 0.02, Medium 0.05, Large 0.08, measured against the photo's shorter edge.
- Border colours (sRGB 0–1):
  - White (1, 1, 1).
  - Off-white (0.98, 0.97, 0.94), which is `0xFFFAF7F0`.
  - Light grey (0.90, 0.90, 0.90), which is `0xFFE6E6E6`.
  - Black (0, 0, 0).
- Ratios: 4:5, 3:4, 191:100, 1:1. Original keeps the photo's own shape.
- Limits: ratio canvases are at least 1080 px wide; long edge capped near 8192 px in the app and near 3072 px in the Share extension; only downscaling, never upscaling.
- Output: JPEG quality 0.92. Instagram presets and Square convert to sRGB; Original keeps the source RGB profile. TIFF, EXIF, EXIF Aux and IPTC are kept; GPS is dropped.
- Batches are capped at 50 photos. Preview re-renders are debounced by 300 ms. In-app previews are 1200 px on the long edge.
- Defaults: Medium border, White, Instagram Portrait 4:5.
- Photo permission is add-only. Usage string: `BorderMe adds your bordered copies to your photo library. It never changes your original photos.`
- User-facing copy uses British spelling ("colour", "grey"), matching the Mac README.

## File map

```
.gitignore                                         add Swift package build dir
mobile/                                            created by `flutter create`
  lib/main.dart                                    app root and theme
  lib/engine/settings.dart                         enums, RenderSettings, wire values
  lib/engine/engine_client.dart                    EngineClient interface, MethodChannelEngine, BatchEvent
  lib/state/session_controller.dart                screen state, preview debounce, batch progress
  lib/screens/home_page.dart                       switches screens by Phase
  lib/screens/start_screen.dart
  lib/screens/edit_screen.dart                     preview pager + SettingsPanel
  lib/screens/settings_panel.dart                  border / colour / size controls
  lib/screens/saving_screen.dart
  lib/screens/done_screen.dart
  test/fake_engine.dart                            in-memory EngineClient for tests
  test/settings_test.dart
  test/session_controller_test.dart
  test/widget_flow_test.dart
  ios/BorderEngine/Package.swift                   Swift package: engine + tests
  ios/BorderEngine/Sources/BorderEngine/Settings.swift
  ios/BorderEngine/Sources/BorderEngine/RenderPlan.swift
  ios/BorderEngine/Sources/BorderEngine/Renderer.swift
  ios/BorderEngine/Tests/BorderEngineTests/RenderPlannerTests.swift
  ios/BorderEngine/Tests/BorderEngineTests/RendererTests.swift
  ios/Shared/SettingsStore.swift                   App Group settings (app + extension)
  ios/Shared/LibraryWriter.swift                   add-only Photos saving
  ios/Shared/PickedFiles.swift                     copy NSItemProvider files to temp
  ios/Shared/FailureReason.swift                   error -> short reason text
  ios/Runner/EnginePlugin.swift                    method channel handler
  ios/Runner/PhotoPicker.swift                     PHPicker presentation
  ios/Runner/BatchProcessor.swift                  batch loop + event stream
  ios/Runner/AppDelegate.swift                     (modify) register EnginePlugin
  ios/Runner/Info.plist                            (modify) usage string, display name
  ios/Runner/Runner.entitlements
  ios/Runner/PrivacyInfo.xcprivacy
  ios/ShareExtension/ShareViewController.swift
  ios/ShareExtension/ShareModel.swift
  ios/ShareExtension/ShareView.swift
  ios/ShareExtension/Info.plist
  ios/ShareExtension/ShareExtension.entitlements
  ios/ShareExtension/PrivacyInfo.xcprivacy
  ios/Runner/Assets.xcassets/AppIcon.appiconset/   (replace) single 1024 icon
  tool/configure_xcode.rb                          idempotent Xcode project wiring
  tool/make_icon.swift                             draws the 1024 px app icon
  store/listing.md                                 App Store text
  store/SUBMITTING.md                              enrollment + upload walkthrough
  store/screenshots/                               simulator screenshots
docs/privacy.html                                  privacy policy page
```

All `mobile/...` commands below run from the repo root unless a step says `cd mobile`. The repo root is `/Users/tomjones/Library/CloudStorage/Dropbox/*DOCS/TOOLS/BorderMe`. Quote it, because of the `*`.

---

### Task 1: Toolchain and Flutter project

**Files:**
- Create: `mobile/` (generated by `flutter create`)
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: a Flutter project at `mobile/` with bundle ID `com.tomlajones.borderme`, Dart package name `borderme`, and an iOS Runner target that builds for the simulator.

- [ ] **Step 1: Install Flutter and Homebrew Ruby with xcodeproj**

```bash
brew install --cask flutter
brew install ruby
"$(brew --prefix ruby)/bin/gem" install xcodeproj
flutter --disable-analytics
```

- [ ] **Step 2: Check the toolchain**

Run: `flutter doctor -v`
Expected: `[✓] Xcode` and `[✓] Flutter`. `[✗] Android toolchain` is fine; Android is out of scope.

- [ ] **Step 3: Create the project**

```bash
cd "/Users/tomjones/Library/CloudStorage/Dropbox/*DOCS/TOOLS/BorderMe"
flutter create --org com.tomlajones --project-name borderme --platforms ios --ios-language swift mobile
```

Expected: `All done!` and a `mobile/ios/Runner.xcodeproj`.

- [ ] **Step 4: Prove the project builds from this folder**

The repo path contains `*` and sits in Dropbox, which can break Xcode build scripts.

Run: `cd mobile && flutter build ios --simulator --debug`
Expected: `✓ Built build/ios/iphonesimulator/Runner.app`.
If it fails with errors pointing at the path (`*DOCS`, "no such file"), **stop and ask Tom** whether to move mobile work to a clone at `~/Developer/BorderMe`. Do not work around it silently.

- [ ] **Step 5: Keep build output out of git and Dropbox**

Append to the root `.gitignore`:

```
mobile/ios/BorderEngine/.build/
```

Tell Dropbox not to sync build folders. The attribute is honoured by Dropbox's File Provider version; it's harmless if ignored:

```bash
mkdir -p mobile/ios/BorderEngine/.build
for d in mobile/build mobile/.dart_tool mobile/ios/BorderEngine/.build; do xattr -w 'com.apple.fileprovider.ignore#P' 1 "$d" 2>/dev/null || true; done
```

- [ ] **Step 6: Run the generated tests**

Run: `cd mobile && flutter test`
Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add .gitignore mobile
git commit -m "Scaffold the BorderMe iPhone app with Flutter"
```

---

### Task 2: Engine settings types and render planning

**Files:**
- Create: `mobile/ios/BorderEngine/Package.swift`
- Create: `mobile/ios/BorderEngine/Sources/BorderEngine/Settings.swift`
- Create: `mobile/ios/BorderEngine/Sources/BorderEngine/RenderPlan.swift`
- Test: `mobile/ios/BorderEngine/Tests/BorderEngineTests/RenderPlannerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `BorderSize` (`.small/.medium/.large`, `fraction: Double`, `label: String`).
  - `BorderColour` (`.white/.offWhite/.lightGrey/.black`, `rgb: (red: Double, green: Double, blue: Double)`, `label`).
  - `SizePreset` (`.instagramPortrait/.instagramTall/.instagramLandscape/.square/.original`, `ratio: (width: Int, height: Int)?`, `convertsToSRGB: Bool`, `shortLabel`). All three enums are `String`-raw-valued with the wire values, and are `CaseIterable` and `Codable`.
  - `RenderSettings` (`border`, `colour`, `size`; `static let standard`; `init(channelValue: Any?)`; `channelValue: [String: String]`).
  - `EngineLimits.appMaximumEdge = 8192`, `EngineLimits.extensionMaximumEdge = 3072`, `EngineLimits.minimumRatioCanvasWidth = 1080`.
  - `RenderPlan` (`canvasWidth`, `canvasHeight`, `imageWidth`, `imageHeight`, `imageOriginX`, `imageOriginY`).
  - `RenderPlanner.plan(sourceWidth:sourceHeight:border:preset:maximumEdge:) -> RenderPlan`.

- [ ] **Step 1: Create the package manifest**

`mobile/ios/BorderEngine/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

// The engine's sources are also compiled straight into the Runner app and the
// Share extension. This package exists so the engine can be tested on a Mac
// with `swift test`, without a simulator.
let package = Package(
    name: "BorderEngine",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "BorderEngine", targets: ["BorderEngine"])],
    targets: [
        .target(name: "BorderEngine"),
        .testTarget(name: "BorderEngineTests", dependencies: ["BorderEngine"])
    ]
)
```

- [ ] **Step 2: Write the failing planner tests**

`mobile/ios/BorderEngine/Tests/BorderEngineTests/RenderPlannerTests.swift`:

```swift
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
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `swift test --package-path mobile/ios/BorderEngine`
Expected: a build failure such as `cannot find 'RenderPlanner' in scope`.

- [ ] **Step 4: Write the settings types**

`mobile/ios/BorderEngine/Sources/BorderEngine/Settings.swift`:

```swift
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
    public static let extensionMaximumEdge = 3_072
    /// Instagram displays posts 1080 px wide, so a narrower canvas would only
    /// be upscaled by Instagram itself.
    public static let minimumRatioCanvasWidth = 1_080
}
```

- [ ] **Step 5: Write the planner (a port of the Mac engine)**

`mobile/ios/BorderEngine/Sources/BorderEngine/RenderPlan.swift`:

```swift
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
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `swift test --package-path mobile/ios/BorderEngine`
Expected: `Executed 7 tests, with 0 failures`.
If a reference size differs, the port has drifted from `BorderMe.workflow/Contents/Resources/BorderMe.swift`. Diff the two functions and fix the port; never edit the expected values.

- [ ] **Step 7: Commit**

```bash
git add mobile/ios/BorderEngine
git commit -m "Port BorderMe's sizing maths into a tested Swift engine"
```

---

### Task 3: Renderer (pixels, colour, metadata)

**Files:**
- Create: `mobile/ios/BorderEngine/Sources/BorderEngine/Renderer.swift`
- Test: `mobile/ios/BorderEngine/Tests/BorderEngineTests/RendererTests.swift`

**Interfaces:**
- Consumes: `RenderSettings`, `RenderPlanner`, `EngineLimits`, `BorderColour.rgb`, `SizePreset.convertsToSRGB` (Task 2).
- Produces:
  - `RenderedImage` (`jpegData: Data`, `width: Int`, `height: Int`).
  - `BorderEngineError` (`.cannotRead/.notAnImage/.animatedImage/.invalidDimensions/.cannotRender/.cannotEncode`, `reason: String`).
  - `Renderer.render(sourceURL:settings:maximumEdge:) throws -> RenderedImage`, a full-size JPEG with metadata.
  - `Renderer.preview(sourceURL:settings:maximumEdge:) throws -> RenderedImage`, a small JPEG without metadata, the same shape as the full render.

- [ ] **Step 1: Write the failing render tests**

`mobile/ios/BorderEngine/Tests/BorderEngineTests/RendererTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `swift test --package-path mobile/ios/BorderEngine --filter RendererTests`
Expected: a build failure such as `cannot find 'Renderer' in scope`.

- [ ] **Step 3: Write the renderer**

`mobile/ios/BorderEngine/Sources/BorderEngine/Renderer.swift`:

```swift
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
        let image = try draw(source: source, plan: plan, outputScale: 1, settings: settings)
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
        let image = try draw(source: source, plan: plan, outputScale: scale, settings: settings)
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
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let rawWidth = integerProperty(properties, key: kCGImagePropertyPixelWidth),
            let rawHeight = integerProperty(properties, key: kCGImagePropertyPixelHeight),
            rawWidth > 0,
            rawHeight > 0
        else {
            throw BorderEngineError.invalidDimensions
        }
        let orientation = integerProperty(properties, key: kCGImagePropertyOrientation) ?? 1
        return (5...8).contains(orientation) ? (rawHeight, rawWidth) : (rawWidth, rawHeight)
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

    private static func colorSpace(for image: CGImage, size: SizePreset) throws -> CGColorSpace {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { throw BorderEngineError.cannotRender }
        guard !size.convertsToSRGB else { return sRGB }
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

    private static func draw(source: CGImageSource, plan: RenderPlan, outputScale: Double, settings: RenderSettings) throws -> CGImage {
        let canvasWidth = max(1, Int((Double(plan.canvasWidth) * outputScale).rounded()))
        let canvasHeight = max(1, Int((Double(plan.canvasHeight) * outputScale).rounded()))
        let imageRect = CGRect(
            x: Double(plan.imageOriginX) * outputScale,
            y: Double(plan.imageOriginY) * outputScale,
            width: Double(plan.imageWidth) * outputScale,
            height: Double(plan.imageHeight) * outputScale
        )

        let decodeEdge = max(1, Int(max(imageRect.width, imageRect.height).rounded(.up)))
        let image = try decodedImage(from: source, maximumPixelSize: decodeEdge)
        let space = try colorSpace(for: image, size: settings.size)
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
        context.draw(image, in: imageRect)

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
```

- [ ] **Step 4: Run all engine tests and confirm they pass**

Run: `swift test --package-path mobile/ios/BorderEngine`
Expected: `Executed 13 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add mobile/ios/BorderEngine
git commit -m "Render bordered JPEGs with colour, profile and metadata handling"
```

---

### Task 4: Native bridge in the Runner app

**Files:**
- Create: `mobile/ios/Shared/SettingsStore.swift`, `mobile/ios/Shared/LibraryWriter.swift`, `mobile/ios/Shared/PickedFiles.swift`, `mobile/ios/Shared/FailureReason.swift`
- Create: `mobile/ios/Runner/EnginePlugin.swift`, `mobile/ios/Runner/PhotoPicker.swift`, `mobile/ios/Runner/BatchProcessor.swift`
- Create: `mobile/ios/Runner/Runner.entitlements`, `mobile/ios/Runner/PrivacyInfo.xcprivacy`
- Create: `mobile/tool/configure_xcode.rb`
- Modify: `mobile/ios/Runner/AppDelegate.swift`, `mobile/ios/Runner/Info.plist`, `mobile/ios/Runner.xcodeproj/project.pbxproj` (via the script only)
- Modify: `docs/superpowers/specs/2026-10-23-borderme-iphone-design.md` (Bridge section)

**Interfaces:**
- Consumes: everything from Tasks 2–3.
- Produces these method channel calls on `borderme/engine`. Arguments are maps, and `settings` is always `{border, colour, size}` with wire values.
  - `pickPhotos {limit:int}` returns `{paths: [String], failed: int}`. While the picked files are being copied, native calls Dart's `pickLoading(count:int)`.
  - `preview {path:String, settings:Map, maxEdge:int}` returns JPEG bytes (`FlutterStandardTypedData`), or `FlutterError(code: "preview_failed", message: reason)`.
  - `process {paths:[String], settings:Map}` returns `nil` straight away; progress arrives on the EventChannel.
  - `lastSettings` returns the settings map; `saveSettings {settings:Map}` returns `nil`.
  - `openSettings` and `openPhotos` return `nil`.
- Produces these events on `borderme/engine/progress`, each a map:
  - `{type:"saved", index:int, thumbnail:String}` (`thumbnail` may be `""`).
  - `{type:"skipped", index:int, reason:String}`.
  - `{type:"stopped", saved:int, total:int}` (low memory).
  - `{type:"finished", saved:int, total:int}`.
  - `{type:"denied"}`.
- Produces for the Share extension (Task 7): `SettingsStore.load() -> RenderSettings`, `SettingsStore.save(_:)`, `LibraryWriter.requestAccess() async -> Bool`, `LibraryWriter.save(jpegData:) async throws`, `PickedFiles.copy(providers:completion:)`, `PickedPhotos(paths:failed:)`, `FailureReason.describe(_ error: Error) -> String`.

This task has no unit test. The pieces are thin wrappers around Photos and Flutter APIs that only exist on a device or simulator. Its checks are a clean simulator build plus a channel smoke test; Task 8 exercises it end to end.

- [ ] **Step 1: Write the shared helpers**

`mobile/ios/Shared/SettingsStore.swift`:

```swift
import Foundation

/// The app and the Share extension read and write the same last-used
/// settings through their shared App Group.
enum SettingsStore {
    static let appGroup = "group.com.tomlajones.borderme"
    private static let key = "lastSettings"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load() -> RenderSettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(RenderSettings.self, from: data)
        else {
            return .standard
        }
        return settings
    }

    static func save(_ settings: RenderSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
```

`mobile/ios/Shared/LibraryWriter.swift`:

```swift
import Photos

enum LibraryWriterError: Error {
    case saveFailed
}

/// Saves new photos with add-only access, the narrowest permission iOS has.
/// BorderMe never reads the photo library.
enum LibraryWriter {
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    static func save(jpegData: Data) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpegData, options: nil)
            }
        } catch {
            throw LibraryWriterError.saveFailed
        }
    }
}
```

`mobile/ios/Shared/PickedFiles.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

struct PickedPhotos {
    let paths: [String]
    let failed: Int
}

/// Copies picked or shared photos into a temporary folder as their original
/// files (HEIC, JPEG, RAW...), metadata intact, so the engine can read them by
/// path. This needs no photo library permission at all.
enum PickedFiles {
    private static let prefix = "Picked-"

    static func freshDirectory() -> URL {
        let temporary = FileManager.default.temporaryDirectory
        let old = (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
        for url in old where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
        let directory = temporary.appendingPathComponent(prefix + UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Calls `completion` on the main queue, keeping the original order.
    static func copy(providers: [NSItemProvider], completion: @escaping (PickedPhotos) -> Void) {
        let directory = freshDirectory()
        let group = DispatchGroup()
        let lock = NSLock()
        var paths: [Int: String] = [:]

        for (index, provider) in providers.enumerated() {
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
            group.enter()
            // The provided file is deleted when this handler returns, so it is
            // copied before leaving. iCloud originals download first.
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                let destination = directory.appendingPathComponent("\(index)-\(url.lastPathComponent)")
                guard (try? FileManager.default.copyItem(at: url, to: destination)) != nil else { return }
                lock.lock()
                paths[index] = destination.path
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            let ordered = paths.keys.sorted().compactMap { paths[$0] }
            completion(PickedPhotos(paths: ordered, failed: providers.count - ordered.count))
        }
    }
}
```

`mobile/ios/Shared/FailureReason.swift`:

```swift
import Foundation

enum FailureReason {
    /// A short reason shown beside a skipped photo.
    static func describe(_ error: Error) -> String {
        if let engineError = error as? BorderEngineError { return engineError.reason }
        if error is LibraryWriterError { return "could not be saved to Photos" }
        return "could not be processed"
    }
}
```

- [ ] **Step 2: Write the Runner bridge**

`mobile/ios/Runner/PhotoPicker.swift`:

```swift
import PhotosUI
import UIKit

final class PhotoPicker: NSObject, PHPickerViewControllerDelegate {
    private var onLoading: ((Int) -> Void)?
    private var completion: ((PickedPhotos) -> Void)?

    func present(limit: Int, onLoading: @escaping (Int) -> Void, completion: @escaping (PickedPhotos) -> Void) {
        // No photo library is passed in, so the picker needs no permission and
        // hands back files rather than library identifiers.
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = limit
        configuration.preferredAssetRepresentationMode = .current

        guard let presenter = UIApplication.shared.topViewController else {
            completion(PickedPhotos(paths: [], failed: 0))
            return
        }
        self.onLoading = onLoading
        self.completion = completion
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let completion else { return }
        self.completion = nil
        if !results.isEmpty { onLoading?(results.count) }
        PickedFiles.copy(providers: results.map(\.itemProvider), completion: completion)
    }
}

extension UIApplication {
    var topViewController: UIViewController? {
        let window = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
```

`mobile/ios/Runner/BatchProcessor.swift`:

```swift
import Flutter
import UIKit

/// Borders a batch one photo at a time, so memory stays bounded, and streams
/// progress to Dart.
final class BatchProcessor: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    private let lock = NSLock()
    private var memoryWarned = false
    private var observer: NSObjectProtocol?

    override init() {
        super.init()
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.setMemoryWarned(true)
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    func start(paths: [String], settings: RenderSettings) {
        setMemoryWarned(false)
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.run(paths: paths, settings: settings)
        }
    }

    private func run(paths: [String], settings: RenderSettings) async {
        guard await LibraryWriter.requestAccess() else {
            emit(["type": "denied"])
            return
        }
        var saved = 0
        for (index, path) in paths.enumerated() {
            // Finish the current photo, then stop, rather than risk iOS ending
            // the app partway through a save.
            if isMemoryWarned() {
                emit(["type": "stopped", "saved": saved, "total": paths.count])
                return
            }
            let url = URL(fileURLWithPath: path)
            do {
                let rendered = try autoreleasepool {
                    try Renderer.render(sourceURL: url, settings: settings, maximumEdge: EngineLimits.appMaximumEdge)
                }
                try await LibraryWriter.save(jpegData: rendered.jpegData)
                saved += 1
                emit(["type": "saved", "index": index, "thumbnail": thumbnail(for: url, settings: settings, index: index) ?? ""])
            } catch {
                emit(["type": "skipped", "index": index, "reason": FailureReason.describe(error)])
            }
        }
        emit(["type": "finished", "saved": saved, "total": paths.count])
    }

    private func thumbnail(for url: URL, settings: RenderSettings, index: Int) -> String? {
        guard let preview = try? Renderer.preview(sourceURL: url, settings: settings, maximumEdge: 300) else { return nil }
        let destination = url.deletingLastPathComponent().appendingPathComponent("thumb-\(index).jpg")
        guard (try? preview.jpegData.write(to: destination)) != nil else { return nil }
        return destination.path
    }

    private func emit(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.sink?(event) }
    }

    private func setMemoryWarned(_ value: Bool) {
        lock.lock()
        memoryWarned = value
        lock.unlock()
    }

    private func isMemoryWarned() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return memoryWarned
    }
}
```

`mobile/ios/Runner/EnginePlugin.swift`:

```swift
import Flutter
import UIKit

final class EnginePlugin: NSObject, FlutterPlugin {
    private let channel: FlutterMethodChannel
    private let picker = PhotoPicker()
    private let batch = BatchProcessor()
    private let previewQueue = DispatchQueue(label: "borderme.preview", qos: .userInitiated)

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "borderme/engine", binaryMessenger: registrar.messenger())
        let instance = EnginePlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        let events = FlutterEventChannel(name: "borderme/engine/progress", binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance.batch)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "pickPhotos":
            let limit = arguments["limit"] as? Int ?? 50
            picker.present(
                limit: limit,
                onLoading: { [channel] count in channel.invokeMethod("pickLoading", arguments: count) },
                completion: { picked in result(["paths": picked.paths, "failed": picked.failed]) }
            )
        case "preview":
            guard let path = arguments["path"] as? String else {
                result(FlutterError(code: "bad_arguments", message: "path is missing", details: nil))
                return
            }
            let settings = RenderSettings(channelValue: arguments["settings"])
            let maxEdge = arguments["maxEdge"] as? Int ?? 1200
            previewQueue.async {
                do {
                    let preview = try Renderer.preview(sourceURL: URL(fileURLWithPath: path), settings: settings, maximumEdge: maxEdge)
                    DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: preview.jpegData)) }
                } catch {
                    let reason = FailureReason.describe(error)
                    DispatchQueue.main.async { result(FlutterError(code: "preview_failed", message: reason, details: nil)) }
                }
            }
        case "process":
            let paths = arguments["paths"] as? [String] ?? []
            batch.start(paths: paths, settings: RenderSettings(channelValue: arguments["settings"]))
            result(nil)
        case "lastSettings":
            result(SettingsStore.load().channelValue)
        case "saveSettings":
            SettingsStore.save(RenderSettings(channelValue: arguments["settings"]))
            result(nil)
        case "openSettings":
            open(UIApplication.openSettingsURLString)
            result(nil)
        case "openPhotos":
            open("photos-redirect://")
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        UIApplication.shared.open(url)
    }
}
```

- [ ] **Step 3: Register the plugin in AppDelegate**

Open `mobile/ios/Runner/AppDelegate.swift` and find the line `GeneratedPluginRegistrant.register(with: X)`.

If `X` is `self`, the classic template, add directly after it:

```swift
EnginePlugin.register(with: self.registrar(forPlugin: "EnginePlugin")!)
```

If the file uses the implicit-engine template, `didInitializeImplicitFlutterEngine(_ engineBridge:)` with `register(with: engineBridge.pluginRegistry)`, add directly after it:

```swift
EnginePlugin.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "EnginePlugin")!)
```

- [ ] **Step 4: Entitlements, privacy manifest and Info.plist**

`mobile/ios/Runner/Runner.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.tomlajones.borderme</string>
	</array>
</dict>
</plist>
```

`mobile/ios/Runner/PrivacyInfo.xcprivacy`. If the Flutter template already created this file, replace its contents. `1C8F.1` is Apple's reason code for UserDefaults shared within an App Group.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>1C8F.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

Then update `Info.plist`:

```bash
PLIST="mobile/ios/Runner/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryAddUsageDescription string 'BorderMe adds your bordered copies to your photo library. It never changes your original photos.'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName BorderMe" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "$PLIST"
```

If an `Add` reports that the key exists, rerun that line with `Set`.

- [ ] **Step 5: Write the Xcode wiring script**

`mobile/tool/configure_xcode.rb`:

```ruby
#!/usr/bin/env ruby
# Wires BorderMe's native code into the Flutter-generated Xcode project.
# Safe to run repeatedly: it only adds what is missing.
#
#   "$(brew --prefix ruby)/bin/ruby" mobile/tool/configure_xcode.rb

require 'xcodeproj'

IOS_DIR = File.expand_path('../ios', __dir__)
project = Xcodeproj::Project.open(File.join(IOS_DIR, 'Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')

def group_for(project, name, path)
  project.main_group.children.find { |c| c.display_name == name } ||
    project.main_group.new_group(name, path)
end

def reference_in(group, filename)
  group.files.find { |f| f.path == filename } || group.new_reference(filename)
end

def add_sources(group, target, filenames)
  filenames.each do |filename|
    target.source_build_phase.add_file_reference(reference_in(group, filename), true)
  end
end

ENGINE_FILES = %w[Settings.swift RenderPlan.swift Renderer.swift].freeze
SHARED_FILES = %w[SettingsStore.swift LibraryWriter.swift PickedFiles.swift FailureReason.swift].freeze
RUNNER_FILES = %w[EnginePlugin.swift PhotoPicker.swift BatchProcessor.swift].freeze

engine_group = group_for(project, 'BorderEngine', 'BorderEngine/Sources/BorderEngine')
shared_group = group_for(project, 'Shared', 'Shared')
runner_group = project.main_group.children.find { |c| c.display_name == 'Runner' } or abort('Runner group not found')

add_sources(engine_group, runner, ENGINE_FILES)
add_sources(shared_group, runner, SHARED_FILES)
add_sources(runner_group, runner, RUNNER_FILES)
runner.resources_build_phase.add_file_reference(reference_in(runner_group, 'PrivacyInfo.xcprivacy'), true)
reference_in(runner_group, 'Runner.entitlements')

runner.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

# --- Share extension (added in Task 7) ---

project.save
puts 'Xcode project configured.'
```

- [ ] **Step 6: Run the script and build**

```bash
"$(brew --prefix ruby)/bin/ruby" mobile/tool/configure_xcode.rb
"$(brew --prefix ruby)/bin/ruby" mobile/tool/configure_xcode.rb
git diff --stat mobile/ios/Runner.xcodeproj/project.pbxproj
```

Expected: `Xcode project configured.` twice. The second run must not add more lines to the pbxproj; compare with `git diff --stat` before and after it.

Run: `cd mobile && flutter build ios --simulator --debug`
Expected: `✓ Built build/ios/iphonesimulator/Runner.app`.

- [ ] **Step 7: Smoke-test the channel**

Temporarily add to the top of `main()` in `mobile/lib/main.dart`, after `WidgetsFlutterBinding.ensureInitialized();` (add that line if missing):

```dart
debugPrint('lastSettings: ${await const MethodChannel('borderme/engine').invokeMethod('lastSettings')}');
```

Make `main` `async` and import `package:flutter/services.dart`. Then run:

```bash
cd mobile && flutter run -d "iPhone 17 Pro"
```

Expected in the log: `lastSettings: {border: medium, colour: white, size: instagram-portrait}` (key order may vary). Quit with `q`, then **revert this temporary change**: `git checkout mobile/lib/main.dart`.

- [ ] **Step 8: Update the spec's Bridge section**

In `docs/superpowers/specs/2026-10-23-borderme-iphone-design.md`, replace the Bridge bullet list and the sentence "Photos are passed as Photos asset identifiers, not bytes, so large images never cross the bridge." with:

```markdown
- `pickPhotos(limit) -> {paths, failed}`: presents the system photo picker with no library access. Picked originals are copied to a temporary folder. Native calls `pickLoading(count)` while the copies are being made.
- `preview(path, settings, maxEdge) -> JPEG bytes`: a small render (about 1200 px) for the live preview.
- `process(paths, settings)`: progress events (`saved`, `skipped`, `stopped`, `finished`, `denied`) on the `borderme/engine/progress` EventChannel.
- `lastSettings() / saveSettings(settings)`: settings shared with the Share extension through an App Group `UserDefaults`.
- `openSettings() / openPhotos()`.

Photos cross the bridge as temporary file paths, never as library identifiers. Reading a library asset by identifier would need full photo-library read access, and BorderMe only asks to add photos.
```

Also replace the bullet "iCloud-only originals are fetched with network access allowed. Their thumbnails show a spinner until they arrive." with "iCloud-only originals are downloaded by the picker before the edit screen opens, behind a single 'Loading photos…' screen. Photos that fail to load are counted on the start screen."

- [ ] **Step 9: Commit**

```bash
git add mobile/ios mobile/tool docs/superpowers/specs
git commit -m "Bridge the Swift engine to Flutter with add-only photo saving"
```

---

### Task 5: Dart engine client, settings and session state

**Files:**
- Create: `mobile/lib/engine/settings.dart`, `mobile/lib/engine/engine_client.dart`, `mobile/lib/state/session_controller.dart`
- Test: `mobile/test/fake_engine.dart`, `mobile/test/settings_test.dart`, `mobile/test/session_controller_test.dart`

**Interfaces:**
- Consumes: the channel contract from Task 4.
- Produces:
  - Enums `BorderSize`, `BorderColour` (with `argb`) and `SizePreset`, each with `wire` and `label`, plus `fromWire(String?)`.
  - `RenderSettings` (`border`, `colour`, `size`, `standard`, `copyWith`, `toMap()`, `RenderSettings.fromMap(Map?)`).
  - `PickResult` (`paths`, `failed`).
  - Sealed `BatchEvent` with `PhotoSaved(index, thumbnailPath)`, `PhotoSkipped(index, reason)`, `BatchStopped(saved, total)`, `BatchFinished(saved, total)` and `PermissionDenied()`; plus `parseBatchEvent(Object?)`.
  - Abstract `EngineClient` and `MethodChannelEngine`.
  - `Phase` (`start`, `loading`, `editing`, `saving`, `done`), `SkippedPhoto` and `SessionController`.

- [ ] **Step 1: Write the fake engine used by every Dart test**

`mobile/test/fake_engine.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:borderme/engine/engine_client.dart';
import 'package:borderme/engine/settings.dart';
import 'package:flutter/services.dart';

final Uint8List kOnePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class FakeEngine implements EngineClient {
  FakeEngine({
    this.pickResult = const PickResult(paths: ['/tmp/a.jpg', '/tmp/b.jpg'], failed: 0),
    List<BatchEvent>? events,
    this.failPreview = false,
    this.stored = RenderSettings.standard,
  }) : events = events ??
            const [
              PhotoSaved(index: 0, thumbnailPath: '/tmp/t0.jpg'),
              PhotoSaved(index: 1, thumbnailPath: '/tmp/t1.jpg'),
              BatchFinished(saved: 2, total: 2),
            ];

  PickResult pickResult;
  List<BatchEvent> events;
  bool failPreview;
  RenderSettings stored;

  final previewRequests = <(String, RenderSettings)>[];
  final savedSettings = <RenderSettings>[];
  List<String>? processedPaths;
  RenderSettings? processedSettings;
  int openedPhotos = 0;
  int openedSettings = 0;
  final _loading = StreamController<int>.broadcast();

  void announceLoading(int count) => _loading.add(count);

  @override
  Stream<int> get pickLoading => _loading.stream;

  @override
  Future<PickResult> pickPhotos({int limit = 50}) async => pickResult;

  @override
  Future<Uint8List> preview(String path, RenderSettings settings, {int maxEdge = 1200}) async {
    previewRequests.add((path, settings));
    if (failPreview) throw PlatformException(code: 'preview_failed', message: 'not a readable image file');
    return kOnePixelPng;
  }

  @override
  Stream<BatchEvent> process(List<String> paths, RenderSettings settings) {
    processedPaths = paths;
    processedSettings = settings;
    return Stream.fromIterable(events);
  }

  @override
  Future<RenderSettings> lastSettings() async => stored;

  @override
  Future<void> saveSettings(RenderSettings settings) async => savedSettings.add(settings);

  @override
  Future<void> openPhotos() async => openedPhotos++;

  @override
  Future<void> openSettings() async => openedSettings++;
}
```

- [ ] **Step 2: Write the failing settings tests**

`mobile/test/settings_test.dart`:

```dart
import 'package:borderme/engine/engine_client.dart';
import 'package:borderme/engine/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wire values match the Swift engine', () {
    expect(BorderSize.values.map((e) => e.wire), ['small', 'medium', 'large']);
    expect(BorderColour.values.map((e) => e.wire), ['white', 'off-white', 'light-grey', 'black']);
    expect(SizePreset.values.map((e) => e.wire),
        ['instagram-portrait', 'instagram-tall', 'instagram-landscape', 'square', 'original']);
  });

  test('settings round-trip through a channel map', () {
    const settings = RenderSettings(border: BorderSize.large, colour: BorderColour.offWhite, size: SizePreset.square);
    expect(settings.toMap(), {'border': 'large', 'colour': 'off-white', 'size': 'square'});
    expect(RenderSettings.fromMap(settings.toMap()), settings);
  });

  test('missing or unknown values fall back to the defaults', () {
    expect(RenderSettings.fromMap(null), RenderSettings.standard);
    expect(RenderSettings.fromMap({'border': 'huge', 'size': 'square'}).border, BorderSize.medium);
    expect(RenderSettings.standard,
        const RenderSettings(border: BorderSize.medium, colour: BorderColour.white, size: SizePreset.instagramPortrait));
  });

  test('colour swatches match the engine colours', () {
    expect(BorderColour.offWhite.argb, 0xFFFAF7F0);
    expect(BorderColour.lightGrey.argb, 0xFFE6E6E6);
  });

  test('batch events parse from native maps', () {
    expect(parseBatchEvent({'type': 'saved', 'index': 1, 'thumbnail': '/t.jpg'}),
        const PhotoSaved(index: 1, thumbnailPath: '/t.jpg'));
    expect(parseBatchEvent({'type': 'skipped', 'index': 2, 'reason': 'not a readable image file'}),
        const PhotoSkipped(index: 2, reason: 'not a readable image file'));
    expect(parseBatchEvent({'type': 'stopped', 'saved': 3, 'total': 9}), const BatchStopped(saved: 3, total: 9));
    expect(parseBatchEvent({'type': 'finished', 'saved': 9, 'total': 9}), const BatchFinished(saved: 9, total: 9));
    expect(parseBatchEvent({'type': 'denied'}), const PermissionDenied());
    expect(parseBatchEvent({'type': 'mystery'}), isNull);
    expect(parseBatchEvent('nonsense'), isNull);
  });
}
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `cd mobile && flutter test test/settings_test.dart`
Expected: FAIL with `Error: Couldn't resolve the package 'borderme' ... engine/settings.dart` or `Undefined name`.

- [ ] **Step 4: Write the settings and engine client**

`mobile/lib/engine/settings.dart`:

```dart
/// Mirrors BorderEngine's Settings.swift. The wire values are the contract
/// with native code and must not change.
enum BorderSize {
  small('small', 'Small'),
  medium('medium', 'Medium'),
  large('large', 'Large');

  const BorderSize(this.wire, this.label);
  final String wire;
  final String label;

  static BorderSize fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => BorderSize.medium);
}

enum BorderColour {
  white('white', 'White', 0xFFFFFFFF),
  offWhite('off-white', 'Off-white', 0xFFFAF7F0),
  lightGrey('light-grey', 'Light grey', 0xFFE6E6E6),
  black('black', 'Black', 0xFF000000);

  const BorderColour(this.wire, this.label, this.argb);
  final String wire;
  final String label;
  final int argb;

  static BorderColour fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => BorderColour.white);
}

enum SizePreset {
  instagramPortrait('instagram-portrait', '4:5 Portrait'),
  instagramTall('instagram-tall', '3:4 Tall'),
  instagramLandscape('instagram-landscape', '1.91:1 Landscape'),
  square('square', '1:1 Square'),
  original('original', 'Original');

  const SizePreset(this.wire, this.label);
  final String wire;
  final String label;

  static SizePreset fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => SizePreset.instagramPortrait);
}

class RenderSettings {
  const RenderSettings({required this.border, required this.colour, required this.size});

  static const standard =
      RenderSettings(border: BorderSize.medium, colour: BorderColour.white, size: SizePreset.instagramPortrait);

  final BorderSize border;
  final BorderColour colour;
  final SizePreset size;

  factory RenderSettings.fromMap(Map<Object?, Object?>? map) => RenderSettings(
        border: BorderSize.fromWire(map?['border'] as String?),
        colour: BorderColour.fromWire(map?['colour'] as String?),
        size: SizePreset.fromWire(map?['size'] as String?),
      );

  Map<String, String> toMap() => {'border': border.wire, 'colour': colour.wire, 'size': size.wire};

  RenderSettings copyWith({BorderSize? border, BorderColour? colour, SizePreset? size}) => RenderSettings(
        border: border ?? this.border,
        colour: colour ?? this.colour,
        size: size ?? this.size,
      );

  @override
  bool operator ==(Object other) =>
      other is RenderSettings && other.border == border && other.colour == colour && other.size == size;

  @override
  int get hashCode => Object.hash(border, colour, size);
}
```

`mobile/lib/engine/engine_client.dart`:

```dart
import 'dart:async';

import 'package:flutter/services.dart';

import 'settings.dart';

class PickResult {
  const PickResult({required this.paths, required this.failed});
  final List<String> paths;
  final int failed;
}

sealed class BatchEvent {
  const BatchEvent();
}

class PhotoSaved extends BatchEvent {
  const PhotoSaved({required this.index, required this.thumbnailPath});
  final int index;
  final String thumbnailPath;

  @override
  bool operator ==(Object other) => other is PhotoSaved && other.index == index && other.thumbnailPath == thumbnailPath;
  @override
  int get hashCode => Object.hash(index, thumbnailPath);
}

class PhotoSkipped extends BatchEvent {
  const PhotoSkipped({required this.index, required this.reason});
  final int index;
  final String reason;

  @override
  bool operator ==(Object other) => other is PhotoSkipped && other.index == index && other.reason == reason;
  @override
  int get hashCode => Object.hash(index, reason);
}

/// The phone ran low on memory, so the batch stopped early.
class BatchStopped extends BatchEvent {
  const BatchStopped({required this.saved, required this.total});
  final int saved;
  final int total;

  @override
  bool operator ==(Object other) => other is BatchStopped && other.saved == saved && other.total == total;
  @override
  int get hashCode => Object.hash(saved, total);
}

class BatchFinished extends BatchEvent {
  const BatchFinished({required this.saved, required this.total});
  final int saved;
  final int total;

  @override
  bool operator ==(Object other) => other is BatchFinished && other.saved == saved && other.total == total;
  @override
  int get hashCode => Object.hash(saved, total);
}

class PermissionDenied extends BatchEvent {
  const PermissionDenied();

  @override
  bool operator ==(Object other) => other is PermissionDenied;
  @override
  int get hashCode => 0;
}

BatchEvent? parseBatchEvent(Object? raw) {
  if (raw is! Map) return null;
  // A typed local, because type promotion of `raw` doesn't reach into the
  // nested function below.
  final Map<Object?, Object?> map = raw;
  int number(String key) => (map[key] as num?)?.toInt() ?? 0;
  return switch (map['type']) {
    'saved' => PhotoSaved(index: number('index'), thumbnailPath: map['thumbnail'] as String? ?? ''),
    'skipped' => PhotoSkipped(index: number('index'), reason: map['reason'] as String? ?? 'could not be processed'),
    'stopped' => BatchStopped(saved: number('saved'), total: number('total')),
    'finished' => BatchFinished(saved: number('saved'), total: number('total')),
    'denied' => const PermissionDenied(),
    _ => null,
  };
}

/// Everything the UI needs from native code. Tests use a fake.
abstract class EngineClient {
  Future<PickResult> pickPhotos({int limit = 50});

  /// Fires once the picker closes and picked photos start copying.
  Stream<int> get pickLoading;

  Future<Uint8List> preview(String path, RenderSettings settings, {int maxEdge = 1200});

  /// Completes after a finished, stopped or denied event.
  Stream<BatchEvent> process(List<String> paths, RenderSettings settings);

  Future<RenderSettings> lastSettings();
  Future<void> saveSettings(RenderSettings settings);
  Future<void> openSettings();
  Future<void> openPhotos();
}

class MethodChannelEngine implements EngineClient {
  MethodChannelEngine() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pickLoading') _pickLoading.add((call.arguments as num?)?.toInt() ?? 0);
      return null;
    });
  }

  static const _channel = MethodChannel('borderme/engine');
  static const _events = EventChannel('borderme/engine/progress');
  final _pickLoading = StreamController<int>.broadcast();

  @override
  Stream<int> get pickLoading => _pickLoading.stream;

  @override
  Future<PickResult> pickPhotos({int limit = 50}) async {
    final raw = await _channel.invokeMapMethod<String, Object?>('pickPhotos', {'limit': limit}) ?? const {};
    return PickResult(
      paths: (raw['paths'] as List<Object?>?)?.cast<String>() ?? const [],
      failed: (raw['failed'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<Uint8List> preview(String path, RenderSettings settings, {int maxEdge = 1200}) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'preview',
      {'path': path, 'settings': settings.toMap(), 'maxEdge': maxEdge},
    );
    if (bytes == null) throw StateError('The engine returned an empty preview.');
    return bytes;
  }

  @override
  Stream<BatchEvent> process(List<String> paths, RenderSettings settings) {
    late final StreamController<BatchEvent> controller;
    StreamSubscription<Object?>? subscription;
    controller = StreamController<BatchEvent>(
      onListen: () {
        // Listen first so no early event is missed, then start the batch.
        subscription = _events.receiveBroadcastStream().listen(
          (raw) {
            final event = parseBatchEvent(raw);
            if (event == null) return;
            controller.add(event);
            if (event is BatchFinished || event is BatchStopped || event is PermissionDenied) {
              subscription?.cancel();
              controller.close();
            }
          },
          onError: controller.addError,
        );
        _channel.invokeMethod<void>('process', {'paths': paths, 'settings': settings.toMap()});
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<RenderSettings> lastSettings() async =>
      RenderSettings.fromMap(await _channel.invokeMapMethod<String, Object?>('lastSettings'));

  @override
  Future<void> saveSettings(RenderSettings settings) =>
      _channel.invokeMethod<void>('saveSettings', {'settings': settings.toMap()});

  @override
  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  @override
  Future<void> openPhotos() => _channel.invokeMethod<void>('openPhotos');
}
```

- [ ] **Step 5: Run the settings tests and confirm they pass**

Run: `cd mobile && flutter test test/settings_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Write the failing session controller tests**

`mobile/test/session_controller_test.dart`:

```dart
import 'package:borderme/engine/engine_client.dart';
import 'package:borderme/engine/settings.dart';
import 'package:borderme/state/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_engine.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('init loads the last-used settings', () async {
    const stored = RenderSettings(border: BorderSize.large, colour: BorderColour.black, size: SizePreset.square);
    final controller = SessionController(FakeEngine(stored: stored), debounce: Duration.zero);
    await controller.init();
    expect(controller.settings, stored);
  });

  test('choosing photos opens the editor and previews the first photo', () async {
    final engine = FakeEngine();
    final controller = SessionController(engine, debounce: Duration.zero);
    await controller.choosePhotos();
    await settle();
    expect(controller.phase, Phase.editing);
    expect(controller.photos, ['/tmp/a.jpg', '/tmp/b.jpg']);
    expect(engine.previewRequests.single.$1, '/tmp/a.jpg');
    expect(controller.previews[0], isNotNull);
  });

  test('the loading screen shows while picked photos copy', () async {
    final engine = FakeEngine();
    final controller = SessionController(engine, debounce: Duration.zero);
    engine.announceLoading(2);
    await settle();
    expect(controller.phase, Phase.loading);
  });

  test('a pick where nothing loads returns to the start and counts failures', () async {
    final engine = FakeEngine(pickResult: const PickResult(paths: [], failed: 3));
    final controller = SessionController(engine, debounce: Duration.zero);
    await controller.choosePhotos();
    expect(controller.phase, Phase.start);
    expect(controller.failedToLoad, 3);
  });

  test('rapid setting changes save each time but preview once', () async {
    final engine = FakeEngine();
    final controller = SessionController(engine, debounce: const Duration(milliseconds: 50));
    await controller.choosePhotos();
    await settle();
    engine.previewRequests.clear();

    controller.updateSettings(controller.settings.copyWith(colour: BorderColour.black));
    controller.updateSettings(controller.settings.copyWith(size: SizePreset.instagramTall));
    controller.updateSettings(controller.settings.copyWith(border: BorderSize.large));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(engine.savedSettings, hasLength(3));
    expect(engine.previewRequests, hasLength(1));
    expect(engine.previewRequests.single.$2,
        const RenderSettings(border: BorderSize.large, colour: BorderColour.black, size: SizePreset.instagramTall));
  });

  test('a preview failure is shown on the current photo', () async {
    final controller = SessionController(FakeEngine(failPreview: true), debounce: Duration.zero);
    await controller.choosePhotos();
    await settle();
    expect(controller.previewError, isNotNull);
  });

  test('saving collects saved and skipped photos, then finishes', () async {
    final engine = FakeEngine(events: const [
      PhotoSaved(index: 0, thumbnailPath: '/tmp/t0.jpg'),
      PhotoSkipped(index: 1, reason: 'not a readable image file'),
      BatchFinished(saved: 1, total: 2),
    ]);
    final controller = SessionController(engine, debounce: Duration.zero);
    await controller.choosePhotos();
    await controller.save();
    expect(engine.processedPaths, ['/tmp/a.jpg', '/tmp/b.jpg']);
    expect(controller.phase, Phase.done);
    expect(controller.saved, 1);
    expect(controller.thumbnails, ['/tmp/t0.jpg']);
    expect(controller.skipped.single.reason, 'not a readable image file');
    expect(controller.stoppedLowMemory, isFalse);
  });

  test('low memory and refused permission are reported', () async {
    final lowMemory = SessionController(
      FakeEngine(events: const [PhotoSaved(index: 0, thumbnailPath: ''), BatchStopped(saved: 1, total: 2)]),
      debounce: Duration.zero,
    );
    await lowMemory.choosePhotos();
    await lowMemory.save();
    expect(lowMemory.stoppedLowMemory, isTrue);
    expect(lowMemory.thumbnails, isEmpty);

    final denied = SessionController(FakeEngine(events: const [PermissionDenied()]), debounce: Duration.zero);
    await denied.choosePhotos();
    await denied.save();
    expect(denied.permissionDenied, isTrue);
    expect(denied.phase, Phase.done);
  });

  test('start again clears the session', () async {
    final controller = SessionController(FakeEngine(), debounce: Duration.zero);
    await controller.choosePhotos();
    controller.startAgain();
    expect(controller.phase, Phase.start);
    expect(controller.photos, isEmpty);
    expect(controller.previews, isEmpty);
  });
}
```

- [ ] **Step 7: Run it and confirm it fails**

Run: `cd mobile && flutter test test/session_controller_test.dart`
Expected: FAIL, `session_controller.dart` not found.

- [ ] **Step 8: Write the session controller**

`mobile/lib/state/session_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/engine_client.dart';
import '../engine/settings.dart';

enum Phase { start, loading, editing, saving, done }

class SkippedPhoto {
  const SkippedPhoto(this.index, this.reason);
  final int index;
  final String reason;
}

class SessionController extends ChangeNotifier {
  SessionController(this.engine, {this.debounce = const Duration(milliseconds: 300)}) {
    _loading = engine.pickLoading.listen((_) {
      if (phase != Phase.start) return;
      phase = Phase.loading;
      notifyListeners();
    });
  }

  static const maxPhotos = 50;

  final EngineClient engine;
  final Duration debounce;
  late final StreamSubscription<int> _loading;
  Timer? _previewTimer;

  Phase phase = Phase.start;
  RenderSettings settings = RenderSettings.standard;
  List<String> photos = const [];
  int failedToLoad = 0;
  int currentIndex = 0;
  final Map<int, Uint8List> previews = {};
  String? previewError;

  int saved = 0;
  int total = 0;
  final List<String> thumbnails = [];
  final List<SkippedPhoto> skipped = [];
  bool stoppedLowMemory = false;
  bool permissionDenied = false;

  int get processed => saved + skipped.length;

  Future<void> init() async {
    settings = await engine.lastSettings();
    notifyListeners();
  }

  Future<void> choosePhotos() async {
    final result = await engine.pickPhotos(limit: maxPhotos);
    failedToLoad = result.failed;
    if (result.paths.isEmpty) {
      phase = Phase.start;
      notifyListeners();
      return;
    }
    photos = result.paths;
    currentIndex = 0;
    previews.clear();
    previewError = null;
    phase = Phase.editing;
    notifyListeners();
    unawaited(_loadPreview(0));
  }

  /// Saves immediately so the Share extension starts from the same settings,
  /// but waits for the user to stop tapping before re-rendering the preview.
  void updateSettings(RenderSettings next) {
    if (next == settings) return;
    settings = next;
    previews.clear();
    previewError = null;
    unawaited(engine.saveSettings(next));
    _previewTimer?.cancel();
    _previewTimer = Timer(debounce, () => _loadPreview(currentIndex));
    notifyListeners();
  }

  void showPhoto(int index) {
    currentIndex = index;
    previewError = null;
    notifyListeners();
    if (!previews.containsKey(index)) unawaited(_loadPreview(index));
  }

  Future<void> _loadPreview(int index) async {
    if (index >= photos.length) return;
    final requested = settings;
    final path = photos[index];
    try {
      final bytes = await engine.preview(path, requested);
      // Settings or photos changed while this was rendering: drop it.
      if (requested != settings || index >= photos.length || photos[index] != path) return;
      previews[index] = bytes;
    } catch (_) {
      if (requested != settings || index != currentIndex) return;
      previewError = "This photo couldn't be previewed. It may be skipped when you save.";
    }
    notifyListeners();
  }

  Future<void> save() async {
    _previewTimer?.cancel();
    phase = Phase.saving;
    saved = 0;
    total = photos.length;
    thumbnails.clear();
    skipped.clear();
    stoppedLowMemory = false;
    permissionDenied = false;
    notifyListeners();

    await for (final event in engine.process(photos, settings)) {
      switch (event) {
        case PhotoSaved(:final thumbnailPath):
          saved++;
          if (thumbnailPath.isNotEmpty) thumbnails.add(thumbnailPath);
        case PhotoSkipped(:final index, :final reason):
          skipped.add(SkippedPhoto(index, reason));
        case BatchStopped():
          stoppedLowMemory = true;
        case BatchFinished():
          break;
        case PermissionDenied():
          permissionDenied = true;
      }
      notifyListeners();
    }
    phase = Phase.done;
    notifyListeners();
  }

  void backToEditing() {
    phase = Phase.editing;
    notifyListeners();
  }

  void startAgain() {
    _previewTimer?.cancel();
    photos = const [];
    previews.clear();
    previewError = null;
    currentIndex = 0;
    failedToLoad = 0;
    phase = Phase.start;
    notifyListeners();
  }

  Future<void> openPhotos() => engine.openPhotos();
  Future<void> openSettings() => engine.openSettings();

  @override
  void dispose() {
    _previewTimer?.cancel();
    _loading.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 9: Run all Dart tests**

Run: `cd mobile && flutter test test/settings_test.dart test/session_controller_test.dart && flutter analyze lib test/fake_engine.dart test/settings_test.dart test/session_controller_test.dart`
Expected: `All tests passed!` and `No issues found!`.

- [ ] **Step 10: Commit**

```bash
git add mobile/lib/engine mobile/lib/state mobile/test/fake_engine.dart mobile/test/settings_test.dart mobile/test/session_controller_test.dart
git commit -m "Add the Dart engine client and session state with tests"
```

---

### Task 6: Screens

**Files:**
- Modify (replace): `mobile/lib/main.dart`
- Create: `mobile/lib/screens/home_page.dart`, `start_screen.dart`, `edit_screen.dart`, `settings_panel.dart`, `saving_screen.dart`, `done_screen.dart`
- Delete: `mobile/test/widget_test.dart` (the template's counter test)
- Test: `mobile/test/widget_flow_test.dart`

**Interfaces:**
- Consumes: `SessionController`, `Phase`, `RenderSettings` and the enums, `MethodChannelEngine` (Task 5).
- Produces: `BorderMeApp(controller:)` and `HomePage(controller:)`. Widget keys used by tests: `Key('choose')`, `Key('save')`, `Key('colour-<wire>')`, `Key('open-photos')`, `Key('start-again')`.

- [ ] **Step 1: Write the failing flow test**

`mobile/test/widget_flow_test.dart`:

```dart
import 'package:borderme/engine/engine_client.dart';
import 'package:borderme/engine/settings.dart';
import 'package:borderme/main.dart';
import 'package:borderme/state/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_engine.dart';

void main() {
  Future<FakeEngine> pumpApp(WidgetTester tester, {FakeEngine? engine}) async {
    final fake = engine ?? FakeEngine();
    final controller = SessionController(fake, debounce: Duration.zero);
    await tester.pumpWidget(BorderMeApp(controller: controller));
    return fake;
  }

  testWidgets('choose, restyle and save two photos', (tester) async {
    final engine = await pumpApp(tester);

    await tester.tap(find.byKey(const Key('choose')));
    await tester.pumpAndSettle();
    expect(find.text('Save 2 photos'), findsOneWidget);

    await tester.tap(find.byKey(const Key('colour-black')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(engine.previewRequests.last.$2.colour, BorderColour.black);

    await tester.tap(find.text('3:4 Tall'));
    await tester.pumpAndSettle();
    expect(engine.savedSettings.last.size, SizePreset.instagramTall);

    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(engine.processedSettings?.colour, BorderColour.black);
    expect(find.text('Saved 2 photos'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-photos')));
    expect(engine.openedPhotos, 1);

    await tester.tap(find.byKey(const Key('start-again')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('choose')), findsOneWidget);
  });

  testWidgets('skipped photos are listed with their reason', (tester) async {
    await pumpApp(tester, engine: FakeEngine(events: const [
      PhotoSaved(index: 0, thumbnailPath: ''),
      PhotoSkipped(index: 1, reason: 'not a readable image file'),
      BatchFinished(saved: 1, total: 2),
    ]));
    await tester.tap(find.byKey(const Key('choose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.text('Saved 1 photo'), findsOneWidget);
    expect(find.text('Photo 2: not a readable image file'), findsOneWidget);
  });

  testWidgets('refused permission explains and links to Settings', (tester) async {
    final engine = await pumpApp(tester, engine: FakeEngine(events: const [PermissionDenied()]));
    await tester.tap(find.byKey(const Key('choose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('permission to add photos'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    expect(engine.openedSettings, 1);
  });

  testWidgets('photos that failed to load are mentioned on the start screen', (tester) async {
    await pumpApp(tester, engine: FakeEngine(pickResult: const PickResult(paths: [], failed: 2)));
    await tester.tap(find.byKey(const Key('choose')));
    await tester.pumpAndSettle();
    expect(find.textContaining("2 photos couldn't be loaded"), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd mobile && rm test/widget_test.dart && flutter test test/widget_flow_test.dart`
Expected: FAIL, `BorderMeApp` isn't defined, or the template's `MyApp` is.

- [ ] **Step 3: Write the app root and screens**

`mobile/lib/main.dart`:

```dart
import 'package:flutter/material.dart';

import 'engine/engine_client.dart';
import 'screens/home_page.dart';
import 'state/session_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = SessionController(MethodChannelEngine());
  controller.init();
  runApp(BorderMeApp(controller: controller));
}

class BorderMeApp extends StatelessWidget {
  const BorderMeApp({super.key, required this.controller});

  final SessionController controller;

  static const _seed = Color(0xFF3D5A80);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BorderMe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark, useMaterial3: true),
      home: HomePage(controller: controller),
    );
  }
}
```

`mobile/lib/screens/home_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../state/session_controller.dart';
import 'done_screen.dart';
import 'edit_screen.dart';
import 'saving_screen.dart';
import 'start_screen.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => switch (controller.phase) {
        Phase.start => StartScreen(controller: controller),
        Phase.loading => const Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading photos…'),
              ]),
            ),
          ),
        Phase.editing => EditScreen(controller: controller),
        Phase.saving => SavingScreen(controller: controller),
        Phase.done => DoneScreen(controller: controller),
      },
    );
  }
}
```

`mobile/lib/screens/start_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../state/session_controller.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final failed = controller.failedToLoad;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('BorderMe', style: textTheme.displaySmall),
              const SizedBox(height: 12),
              Text(
                'Clean borders for your photos, with nothing cropped.',
                style: textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                key: const Key('choose'),
                onPressed: controller.choosePhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose photos'),
              ),
              if (failed > 0) ...[
                const SizedBox(height: 16),
                Text(
                  failed == 1 ? "1 photo couldn't be loaded." : "$failed photos couldn't be loaded.",
                  style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
```

`mobile/lib/screens/settings_panel.dart`:

```dart
import 'package:flutter/material.dart';

import '../engine/settings.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.settings, required this.onChanged});

  final RenderSettings settings;
  final ValueChanged<RenderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('Border', style: labelStyle),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<BorderSize>(
          showSelectedIcon: false,
          segments: [for (final b in BorderSize.values) ButtonSegment(value: b, label: Text(b.label))],
          selected: {settings.border},
          onSelectionChanged: (s) => onChanged(settings.copyWith(border: s.first)),
        ),
      ),
      const SizedBox(height: 16),
      Text('Colour', style: labelStyle),
      const SizedBox(height: 6),
      Row(children: [for (final c in BorderColour.values) _Swatch(colour: c, selected: c == settings.colour, onTap: () => onChanged(settings.copyWith(colour: c)))]),
      const SizedBox(height: 16),
      Text('Size', style: labelStyle),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in SizePreset.values)
          ChoiceChip(
            label: Text(s.label),
            selected: s == settings.size,
            onSelected: (_) => onChanged(settings.copyWith(size: s)),
          ),
      ]),
    ]);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colour, required this.selected, required this.onTap});

  final BorderColour colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Semantics(
        button: true,
        selected: selected,
        label: colour.label,
        child: InkResponse(
          key: Key('colour-${colour.wire}'),
          onTap: onTap,
          radius: 26,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(colour.argb),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

`mobile/lib/screens/edit_screen.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../state/session_controller.dart';
import 'settings_panel.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final PageController _pages = PageController(initialPage: widget.controller.currentIndex);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final count = c.photos.length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Start again', onPressed: c.startAgain),
        title: Text(count == 1 ? '1 photo' : '${c.currentIndex + 1} of $count'),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: count,
              onPageChanged: c.showPhoto,
              itemBuilder: (context, i) => _Preview(
                bytes: c.previews[i],
                error: i == c.currentIndex ? c.previewError : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SettingsPanel(settings: c.settings, onChanged: c.updateSettings),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('save'),
                onPressed: c.save,
                child: Text(count == 1 ? 'Save 1 photo' : 'Save $count photos'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.bytes, required this.error});

  final Uint8List? bytes;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final image = bytes;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: image != null
            ? DecoratedBox(
                decoration: const BoxDecoration(boxShadow: [BoxShadow(blurRadius: 12, color: Color(0x33000000))]),
                child: Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true),
              )
            : error != null
                ? Text(error!, textAlign: TextAlign.center)
                : const CircularProgressIndicator(),
      ),
    );
  }
}
```

`mobile/lib/screens/saving_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../state/session_controller.dart';

class SavingScreen extends StatelessWidget {
  const SavingScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.total;
    final current = (controller.processed + 1).clamp(1, total == 0 ? 1 : total);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Saving $current of $total', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: total == 0 ? 0 : controller.processed / total),
            ]),
          ),
        ),
      ),
    );
  }
}
```

`mobile/lib/screens/done_screen.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../state/session_controller.dart';

class DoneScreen extends StatelessWidget {
  const DoneScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final textTheme = Theme.of(context).textTheme;

    if (c.permissionDenied) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              Text('BorderMe needs permission to add photos', style: textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                "Your photos weren't saved. Allow BorderMe to add photos in Settings, then try again. "
                'It only ever adds new copies; it never reads or changes your library.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: c.openSettings, child: const Text('Open Settings')),
              TextButton(onPressed: c.backToEditing, child: const Text('Back to photos')),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text(c.saved == 1 ? 'Saved 1 photo' : 'Saved ${c.saved} photos', style: textTheme.headlineSmall),
          if (c.stoppedLowMemory) ...[
            const SizedBox(height: 8),
            Text('Your iPhone ran low on memory, so BorderMe stopped after ${c.saved} of ${c.total}. '
                'Try the rest in a smaller batch.'),
          ],
          if (c.thumbnails.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: c.thumbnails.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Image.file(
                  File(c.thumbnails[i]),
                  height: 120,
                  errorBuilder: (_, __, ___) => Container(width: 96, color: Colors.black12),
                ),
              ),
            ),
          ],
          if (c.skipped.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Skipped', style: textTheme.titleMedium),
            for (final s in c.skipped)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Photo ${s.index + 1}: ${s.reason}'),
              ),
          ],
          const SizedBox(height: 32),
          FilledButton(key: const Key('open-photos'), onPressed: c.openPhotos, child: const Text('Open Photos')),
          const SizedBox(height: 8),
          OutlinedButton(key: const Key('start-again'), onPressed: c.startAgain, child: const Text('Start again')),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the whole Dart suite and analyzer**

Run: `cd mobile && flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`.

- [ ] **Step 5: Build for the simulator**

Run: `cd mobile && flutter build ios --simulator --debug`
Expected: `✓ Built build/ios/iphonesimulator/Runner.app`.

- [ ] **Step 6: Commit**

```bash
git add -A mobile/lib mobile/test
git commit -m "Build the BorderMe screens: pick, preview, save, results"
```

---

### Task 7: Share-sheet extension

**Files:**
- Create: `mobile/ios/ShareExtension/ShareViewController.swift`, `ShareModel.swift`, `ShareView.swift`, `Info.plist`, `ShareExtension.entitlements`, `PrivacyInfo.xcprivacy`
- Modify: `mobile/tool/configure_xcode.rb` (fill in the Share extension section)

**Interfaces:**
- Consumes: `Renderer`, `RenderSettings` and its enums with `label` and `shortLabel`, `EngineLimits.extensionMaximumEdge` (Tasks 2–3); `SettingsStore`, `LibraryWriter`, `PickedFiles`, `FailureReason` (Task 4).
- Produces: a `ShareExtension` target embedded in Runner, offered for up to 50 images from the Photos app.

- [ ] **Step 1: Write the extension's model, view and controller**

`mobile/ios/ShareExtension/ShareModel.swift`:

```swift
import SwiftUI
import UIKit

/// All updates to published state happen on the main queue.
final class ShareModel: ObservableObject {
    enum Stage: Equatable {
        case loading
        case ready
        case saving(done: Int, total: Int)
        case finished(saved: Int, skipped: [String])
        case failed(String)
    }

    @Published var settings: RenderSettings {
        didSet {
            SettingsStore.save(settings)
            refreshPreview()
        }
    }
    @Published private(set) var stage: Stage = .loading
    @Published private(set) var preview: UIImage?
    private(set) var paths: [String] = []
    private let renderQueue = DispatchQueue(label: "borderme.share.render", qos: .userInitiated)

    init() {
        settings = SettingsStore.load()
    }

    func load(providers: [NSItemProvider]) {
        PickedFiles.copy(providers: providers) { [weak self] picked in
            guard let self else { return }
            self.paths = picked.paths
            if picked.paths.isEmpty {
                self.stage = .failed("BorderMe couldn't open these photos.")
            } else {
                self.stage = .ready
                self.refreshPreview()
            }
        }
    }

    func refreshPreview() {
        guard let first = paths.first else { return }
        let requested = settings
        renderQueue.async { [weak self] in
            let rendered = try? Renderer.preview(sourceURL: URL(fileURLWithPath: first), settings: requested, maximumEdge: 900)
            let image = rendered.flatMap { UIImage(data: $0.jpegData) }
            DispatchQueue.main.async {
                guard let self, self.settings == requested else { return }
                self.preview = image
            }
        }
    }

    func save() {
        let paths = self.paths
        let settings = self.settings
        stage = .saving(done: 0, total: paths.count)
        Task.detached(priority: .userInitiated) { [weak self] in
            guard await LibraryWriter.requestAccess() else {
                self?.setStage(.failed("BorderMe needs permission to add photos. You can allow it in Settings > Privacy & Security > Photos."))
                return
            }
            var saved = 0
            var skipped: [String] = []
            for (index, path) in paths.enumerated() {
                do {
                    // Extensions get far less memory than apps, hence the smaller cap.
                    let rendered = try autoreleasepool {
                        try Renderer.render(
                            sourceURL: URL(fileURLWithPath: path),
                            settings: settings,
                            maximumEdge: EngineLimits.extensionMaximumEdge
                        )
                    }
                    try await LibraryWriter.save(jpegData: rendered.jpegData)
                    saved += 1
                } catch {
                    skipped.append("Photo \(index + 1): \(FailureReason.describe(error))")
                }
                self?.setStage(.saving(done: index + 1, total: paths.count))
            }
            self?.setStage(.finished(saved: saved, skipped: skipped))
        }
    }

    private func setStage(_ next: Stage) {
        DispatchQueue.main.async { [weak self] in self?.stage = next }
    }
}
```

`mobile/ios/ShareExtension/ShareView.swift`:

```swift
import SwiftUI

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let onDone: () -> Void

    var body: some View {
        NavigationView {
            content
                .navigationTitle("BorderMe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onDone)
                    }
                }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .loading:
            ProgressView("Opening photos…")
        case .failed(let message):
            VStack(spacing: 16) {
                Text(message).multilineTextAlignment(.center)
                Button("Close", action: onDone)
            }
            .padding()
        case .ready:
            editor
        case .saving(let done, let total):
            ProgressView(value: Double(done), total: Double(max(total, 1))) {
                Text("Saving \(min(done + 1, total)) of \(total)")
            }
            .padding()
        case .finished(let saved, let skipped):
            VStack(spacing: 12) {
                Text(saved == 1 ? "Saved 1 photo" : "Saved \(saved) photos").font(.headline)
                ForEach(skipped, id: \.self) { line in
                    Text(line).font(.footnote).foregroundColor(.secondary)
                }
                Button("Done", action: onDone).buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var editor: some View {
        VStack(spacing: 16) {
            Group {
                if let preview = model.preview {
                    Image(uiImage: preview).resizable().scaledToFit().shadow(radius: 4)
                } else {
                    ProgressView()
                }
            }
            .frame(maxHeight: 280)

            Picker("Border", selection: $model.settings.border) {
                ForEach(BorderSize.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Colour", selection: $model.settings.colour) {
                ForEach(BorderColour.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Size", selection: $model.settings.size) {
                ForEach(SizePreset.allCases, id: \.self) { Text($0.shortLabel).tag($0) }
            }
            .pickerStyle(.segmented)

            Button {
                model.save()
            } label: {
                Text(model.paths.count == 1 ? "Save 1 photo" : "Save \(model.paths.count) photos")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}
```

`mobile/ios/ShareExtension/ShareViewController.swift`:

```swift
import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        model.load(providers: items.flatMap { $0.attachments ?? [] })
    }
}
```

- [ ] **Step 2: Write the extension's plists**

`mobile/ios/ShareExtension/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>BorderMe</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>NSPhotoLibraryAddUsageDescription</key>
	<string>BorderMe adds your bordered copies to your photo library. It never changes your original photos.</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionAttributes</key>
		<dict>
			<key>NSExtensionActivationRule</key>
			<dict>
				<key>NSExtensionActivationSupportsImageWithMaxCount</key>
				<integer>50</integer>
			</dict>
		</dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.share-services</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
	</dict>
</dict>
</plist>
```

`mobile/ios/ShareExtension/ShareExtension.entitlements`: same contents as `Runner.entitlements` (Task 4, Step 4).
`mobile/ios/ShareExtension/PrivacyInfo.xcprivacy`: same contents as `Runner/PrivacyInfo.xcprivacy` (Task 4, Step 4).

```bash
cp mobile/ios/Runner/Runner.entitlements mobile/ios/ShareExtension/ShareExtension.entitlements
cp mobile/ios/Runner/PrivacyInfo.xcprivacy mobile/ios/ShareExtension/PrivacyInfo.xcprivacy
```

- [ ] **Step 3: Add the extension target to the wiring script**

In `mobile/tool/configure_xcode.rb`, replace the line `# --- Share extension (added in Task 7) ---` with:

```ruby
# --- Share extension ---

EXTENSION_NAME = 'ShareExtension'
EXTENSION_FILES = %w[ShareViewController.swift ShareModel.swift ShareView.swift].freeze

extension = project.targets.find { |t| t.name == EXTENSION_NAME }
unless extension
  extension = project.new_target(:app_extension, EXTENSION_NAME, :ios, '16.0')
  runner.add_dependency(extension)
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.dst_subfolder_spec = '13'
  embedded = embed.add_file_reference(extension.product_reference, true)
  embedded.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  # Flutter's "Thin Binary" script must run after the extension is embedded,
  # otherwise Xcode reports a dependency cycle in Runner.
  thin = runner.build_phases.find { |p| p.display_name == 'Thin Binary' }
  if thin
    runner.build_phases.delete(embed)
    runner.build_phases.insert(runner.build_phases.index(thin), embed)
  end
end
extension.add_build_configuration('Profile', :release) unless extension.build_configurations.any? { |c| c.name == 'Profile' }

extension_group = group_for(project, EXTENSION_NAME, EXTENSION_NAME)
add_sources(extension_group, extension, EXTENSION_FILES)
add_sources(engine_group, extension, ENGINE_FILES)
add_sources(shared_group, extension, SHARED_FILES)
extension.resources_build_phase.add_file_reference(reference_in(extension_group, 'PrivacyInfo.xcprivacy'), true)
%w[Info.plist ShareExtension.entitlements].each { |f| reference_in(extension_group, f) }

# The extension shares Runner's Flutter xcconfig, which provides
# FLUTTER_BUILD_NAME and FLUTTER_BUILD_NUMBER, so both report the same version.
runner_bases = runner.build_configurations.to_h { |c| [c.name, c.base_configuration_reference] }
extension.build_configurations.each do |config|
  config.base_configuration_reference = runner_bases[config.name] || runner_bases['Release']
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.tomlajones.borderme.share'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['INFOPLIST_FILE'] = 'ShareExtension/Info.plist'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['CODE_SIGN_ENTITLEMENTS'] = 'ShareExtension/ShareExtension.entitlements'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  settings['SKIP_INSTALL'] = 'YES'
  settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end
```

- [ ] **Step 4: Run the script twice and build**

```bash
"$(brew --prefix ruby)/bin/ruby" mobile/tool/configure_xcode.rb
"$(brew --prefix ruby)/bin/ruby" mobile/tool/configure_xcode.rb
cd mobile && flutter build ios --simulator --debug
ls build/ios/iphonesimulator/Runner.app/PlugIns
```

Expected: `Xcode project configured.` twice, with the second run changing nothing in the pbxproj. The build prints `✓ Built ...Runner.app`, and `PlugIns` lists `ShareExtension.appex`.
If the build fails with `Cycle inside Runner`, the embed phase isn't before `Thin Binary`. Print `runner.build_phases.map(&:display_name)` from the script and fix the ordering.

- [ ] **Step 5: Commit**

```bash
git add mobile/ios mobile/tool
git commit -m "Add the BorderMe Share-sheet extension"
```

---

### Task 8: End-to-end check in the simulator

**Files:**
- Create: none (verification only). Fix bugs found here in the file that owns them and re-run that task's tests.

**Interfaces:**
- Consumes: the built app from Tasks 1–7.
- Produces: a verified build, and notes on anything that couldn't be verified.

- [ ] **Step 1: Make test photos and load them into a simulator**

```bash
SCRATCH="$(mktemp -d)"
sips -s format jpeg "/System/Library/Desktop Pictures/iMac Blue.heic" --out "$SCRATCH/sq.jpg"
sips -z 6000 4000 "$SCRATCH/sq.jpg" --out "$SCRATCH/portrait-4000x6000.jpg"
sips -z 4000 6000 "$SCRATCH/sq.jpg" --out "$SCRATCH/landscape-6000x4000.jpg"
UDID=$(xcrun simctl list devices available | awk -F'[()]' '/iPhone 17 Pro \(/{print $2; exit}')
xcrun simctl boot "$UDID" || true
xcrun simctl addmedia "$UDID" "$SCRATCH/portrait-4000x6000.jpg" "$SCRATCH/landscape-6000x4000.jpg"
touch "$SCRATCH/marker"
echo "$UDID $SCRATCH"
```

- [ ] **Step 2: Install and drive the app**

Open the simulator panel with the iOS Simulator tool (`attach`). Then:

```bash
cd mobile && flutter build ios --simulator --debug
```

Launch `mobile/build/ios/iphonesimulator/Runner.app` with the simulator tool (`launch`). Then:

1. Tap **Choose photos** and select both test photos.
2. Confirm the edit screen shows a preview with a white 4:5 border.
3. Tap the **Black** swatch and confirm the preview turns black within about a second.
4. Tap **3:4 Tall**.
5. Swipe to the second photo and confirm it previews.
6. Tap **Save 2 photos**. When the system asks about adding photos, allow it.
7. Confirm the screen reads **Saved 2 photos** with two thumbnails.

Take a screenshot at the edit and done screens.

- [ ] **Step 3: Check the saved files**

```bash
MEDIA="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Media/DCIM"
find "$MEDIA" -type f -newer "$SCRATCH/marker" \( -iname '*.jpg' -o -iname '*.jpeg' \) -exec sips -g pixelWidth -g pixelHeight {} \;
```

Expected: one 4800 x 6400 and one 6144 x 8192 file (3:4, Medium border), matching the reference table.

- [ ] **Step 4: Check the Share extension and shared settings**

1. Open the Photos app in the simulator, select the landscape test photo, tap **Share**, then **BorderMe**. If BorderMe isn't listed, tap **Edit Actions** and enable it.
2. Confirm the sheet opens with **Black** and **3:4** already selected; this proves the App Group settings work.
3. Tap **Save 1 photo** and then **Done**.
4. Re-run the Step 3 `find` command. Expected: a new 3:4 file with a long edge of 3072–3080 px.

If the sheet opens with White/4:5 instead, the App Group isn't shared in this simulator build. Note it for the device test after enrollment rather than changing code: App Groups only fully apply once the app is signed with a team.

- [ ] **Step 5: Check refused permission**

```bash
xcrun simctl privacy "$UDID" revoke photos-add com.tomlajones.borderme
```

In the app, tap **Start again**, choose one photo and save. Expected: the "BorderMe needs permission to add photos" screen with **Open Settings**. Then restore access:

```bash
xcrun simctl privacy "$UDID" grant photos-add com.tomlajones.borderme
```

- [ ] **Step 6: Record results**

Write a short summary in the task's final report:
- What passed.
- Any file sizes that differed from the expected values.
- What couldn't be verified. The low-memory stop is covered only by unit tests; real-device performance isn't checked yet.

Commit any fixes made during this task with messages naming the bug.

---

### Task 9: App icon, store listing, privacy policy and submission guide

**Files:**
- Create: `mobile/tool/make_icon.swift`
- Replace: `mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/` (single 1024 icon)
- Create: `mobile/store/listing.md`, `mobile/store/SUBMITTING.md`, `mobile/store/screenshots/*.png`, `docs/privacy.html`

**Interfaces:**
- Consumes: the working app (Task 8).
- Produces: everything App Store Connect asks for except the Developer account.

- [ ] **Step 1: Draw the icon**

`mobile/tool/make_icon.swift`:

```swift
// Draws BorderMe's 1024 px app icon: a sunset "photo" on a thick white
// border, on a soft warm background. No transparency, as Apple requires.
//
//   swift mobile/tool/make_icon.swift mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

func colour(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, 1])!
}

context.setFillColor(colour(0.93, 0.91, 0.88))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

let frame = CGRect(x: 192, y: 152, width: 640, height: 720)
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: colour(0, 0, 0).copy(alpha: 0.25))
context.setFillColor(colour(1, 1, 1))
context.fill(frame)
context.setShadow(offset: .zero, blur: 0, color: nil)

let photo = frame.insetBy(dx: 64, dy: 64)
context.saveGState()
context.clip(to: photo)
let gradient = CGGradient(
    colorsSpace: space,
    colors: [colour(0.98, 0.62, 0.36), colour(0.85, 0.36, 0.42), colour(0.24, 0.35, 0.56)] as CFArray,
    locations: [0, 0.5, 1]
)!
context.drawLinearGradient(gradient, start: CGPoint(x: photo.midX, y: photo.maxY), end: CGPoint(x: photo.midX, y: photo.minY), options: [])
context.setFillColor(colour(1, 0.86, 0.55))
context.fillEllipse(in: CGRect(x: photo.midX - 70, y: photo.midY - 40, width: 140, height: 140))
context.setFillColor(colour(0.16, 0.22, 0.36))
context.fill(CGRect(x: photo.minX, y: photo.minY, width: photo.width, height: photo.height * 0.32))
context.restoreGState()

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(output.path)") }
print("wrote \(output.path)")
```

```bash
ICONSET=mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset
rm -f "$ICONSET"/*.png
swift mobile/tool/make_icon.swift "$ICONSET/AppIcon-1024.png"
cat > "$ICONSET/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
sips -g pixelWidth -g pixelHeight -g hasAlpha "$ICONSET/AppIcon-1024.png"
```

Expected: 1024 x 1024 and `hasAlpha: no`. View the PNG to check it looks right, then rebuild (`flutter build ios --simulator --debug`) and confirm the home-screen icon in the simulator.

- [ ] **Step 2: Store screenshots**

Boot an **iPhone 17 Pro Max** simulator (the 6.9-inch size App Store Connect requires) and load the Task 8 test photos the same way. Run the app there, then capture three screens: start, edit with a preview showing, and done.

```bash
mkdir -p mobile/store/screenshots
xcrun simctl io booted screenshot mobile/store/screenshots/01-start.png
xcrun simctl io booted screenshot mobile/store/screenshots/02-edit.png
xcrun simctl io booted screenshot mobile/store/screenshots/03-done.png
```

Navigate to each screen before its command. Check each file opens and shows the right screen.

- [ ] **Step 3: Write the store listing in Tom's voice**

**Invoke the `my-voice` skill first.** Then write `mobile/store/listing.md` with these fields, keeping to the App Store limits:
- **Name:** `BorderMe` (30 characters max).
- **Subtitle:** 30 characters max, for example about clean borders with nothing cropped.
- **Promotional text:** 170 characters max.
- **Description:** 4000 characters max. Cover:
  - Your whole photo, never cropped.
  - Exact 4:5, 3:4, 1.91:1 and 1:1 shapes.
  - Full resolution.
  - Four border colours.
  - Batches of up to 50.
  - The Share sheet.
  - Location removed, copyright kept.
  - No accounts and no data collected.
  - Free.
- **Keywords:** comma-separated, 100 characters max.
- **Support URL:** `https://github.com/tomlajones/BorderMe`.
- **Privacy policy URL:** the GitHub Pages address from Step 4.
- **Category:** Photo & Video.
- **Age rating:** 4+, with no objectionable content.
- **App Privacy:** Data Not Collected.

Check the character counts with `wc -m` on each field.

- [ ] **Step 4: Privacy policy page**

**Invoke the `my-voice` skill** (already loaded from Step 3), then write `docs/privacy.html`: a single self-contained page with a `<title>BorderMe Privacy</title>`, readable at phone width. It says, in Tom's voice:
- BorderMe collects no data and has no accounts, analytics or network access.
- Photos are processed only on the device.
- The app asks only to add photos, never to read the library.
- Location is removed from bordered copies.
- Contact is through GitHub issues.

Include today's date.

Publishing it is outward-facing. **Ask Tom before enabling GitHub Pages.** If he agrees, enable Pages for `main` / `docs`:

```bash
gh api -X POST repos/tomlajones/BorderMe/pages -f "source[branch]=main" -f "source[path]=/docs"
```

The URL will be `https://tomlajones.github.io/BorderMe/privacy.html`. Put it in `listing.md`.

- [ ] **Step 5: Submission guide**

Write `mobile/store/SUBMITTING.md` as a numbered walkthrough for after enrollment:

1. Enroll at developer.apple.com/programs ($99/year) and wait for approval.
2. In Xcode, open `mobile/ios/Runner.xcworkspace` (or `Runner.xcodeproj` if there's no workspace).
   - For both the **Runner** and **ShareExtension** targets, open **Signing & Capabilities**, choose your team and keep "Automatically manage signing" on.
   - Under **App Groups**, tick `group.com.tomlajones.borderme` for both targets. Xcode registers it.
3. Test on your iPhone: connect it, then run `flutter run --release` from `mobile`. Check the Share sheet keeps your last settings.
4. In App Store Connect, create the app: bundle ID `com.tomlajones.borderme`, SKU `borderme-ios`, primary language English (UK).
5. Build and upload:
   - `cd mobile && flutter build ipa --release`.
   - Upload `build/ios/ipa/*.ipa` with Apple's Transporter app, or open the archive in Xcode's Organizer and choose Distribute.
6. Fill in the listing from `listing.md` and add the screenshots from `store/screenshots`.
   - **App Privacy:** "Data Not Collected".
   - **Export compliance:** already answered "No" through `ITSAppUsesNonExemptEncryption`.
7. Price: Free. Availability: all countries.
8. Submit for review. In the review notes, say there's no login, that the Share extension appears under Share in Photos, and that the app only requests add-only photo access.

- [ ] **Step 6: Mention the iPhone app in the README**

Add a short section to the root `README.md`, after "## Use", in the same voice:

```markdown
## iPhone

There's an iPhone version in `mobile/` too, built with Flutter, with the same borders and sizes, a live preview, four border colours, and a Share-sheet action from the Photos app. It isn't on the App Store yet.
```

- [ ] **Step 7: Run everything once more and commit**

```bash
swift test --package-path mobile/ios/BorderEngine
(cd mobile && flutter test && flutter analyze && flutter build ios --simulator --debug)
git add mobile docs/privacy.html README.md
git commit -m "Add the app icon, App Store listing, privacy policy and submission guide"
```

Expected: every test passes, analysis is clean and the build succeeds.
