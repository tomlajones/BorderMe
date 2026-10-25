# BorderMe for iPhone: Design

**Date:** 2026-10-23
**Status:** Approved design, awaiting spec review

## Goal

An iPhone app that does what the BorderMe Mac Quick Action does: put photos on a clean border, sized for Instagram or kept at original resolution, without cropping the photo and without losing resolution. It ships free on the App Store to anyone.

## Decisions

| Topic | Decision |
|---|---|
| Audience | Public, App Store |
| Price | Free. No in-app purchases, no ads. |
| Framework | Flutter for the UI, with a native image engine per platform |
| Platforms | iPhone in release 1. Android is release 2, with its own Kotlin engine and a Google Play account. |
| Input | In-app photo picker (multi-select), plus a Share-sheet extension from Photos |
| Output | New JPEGs saved to the photo library. Originals are never modified. |
| Extras beyond the Mac | Live preview, border colour choice, batch processing, Square 1:1 preset |
| Developer account | Not enrolled yet. Build and test in the simulator first; enroll before TestFlight/App Store. |

## Repository layout

The app lives in the existing BorderMe repo, beside the Mac Quick Action:

```
BorderMe/
  BorderMe.workflow/        Mac Quick Action (unchanged)
  mobile/                   Flutter project
    lib/                    Dart UI
    ios/Runner/             Flutter host app + native engine bridge
    ios/BorderEngine/       Swift image engine (shared by app and extension)
    ios/ShareExtension/     Native Share-sheet extension
    test/                   Dart tests (sizing maths, UI state)
  docs/superpowers/specs/   This document
```

## Architecture

Two layers, with a narrow boundary between them.

**Flutter (Dart): everything you see.** Photo selection, controls, preview display, batch progress, results and errors. Dart never touches full-resolution pixels.

**Native engine (Swift): everything that touches pixels.** It is a direct port of `BorderMe.workflow/Contents/Resources/BorderMe.swift` (CoreGraphics + ImageIO), split into:

- `RenderPlan`: pure sizing maths. Given source dimensions, border and preset, it returns canvas and image rectangles. No image I/O, so it is unit-testable.
- `Renderer`: decodes, draws onto the border colour, and encodes JPEG with preserved metadata.
- `LibraryWriter`: saves the result to Photos as a new asset.

**Bridge.** A Flutter `MethodChannel` named `borderme/engine` with these calls:

- `pickPhotos(limit) -> {paths, failed}`: presents the system photo picker with no library access. Picked originals are copied to a temporary folder. Native calls `pickLoading(count)` while the copies are being made.
- `preview(path, settings, maxEdge) -> JPEG bytes`: a small render (about 1200 px) for the live preview.
- `process(paths, settings)`: progress events (`saved`, `skipped`, `stopped`, `finished`, `denied`) on the `borderme/engine/progress` EventChannel.
- `lastSettings() / saveSettings(settings)`: settings shared with the Share extension through an App Group `UserDefaults`.
- `openSettings() / openPhotos()`.

Photos cross the bridge as temporary file paths, never as library identifiers. Reading a library asset by identifier would need full photo-library read access, and BorderMe only asks to add photos.

**Share extension.** Native Swift and SwiftUI, because Flutter cannot run inside an app extension. It links the same `BorderEngine` sources, shows a compact version of the three controls and a small preview, starts from the last-used settings, and saves on one tap.

## Presets

**Border thickness**, measured against the photo's shorter edge (same as the Mac):

- Small 2%
- Medium 5%
- Large 8%

**Border colour:** White (default), Off-white, Light grey, Black. A fixed list.

**Size:**

| Preset | Ratio | Notes |
|---|---|---|
| Instagram Portrait (default) | exactly 4:5 | Works everywhere |
| Instagram Tall | exactly 3:4 | Native in the Instagram app |
| Instagram Landscape | exactly 1.91:1 (191:100) | |
| Square | exactly 1:1 | New on iPhone |
| Original | photo + border | Full resolution, keeps colour profile |

The Mac's Small (1200 px) and Medium (2400 px) output sizes are not included.

## Sizing rules (ported from the Mac engine)

- The canvas is `ratio.width x ratio.height` multiplied by a whole number, so ratios are exact.
- The canvas is the smallest that fits the photo plus its border on all sides. The spare axis gets extra border.
- Photos are never cropped and never upscaled. A canvas is at least 1080 px wide.
- The long-edge cap is about 8192 px in the app and about 4096 px in the Share extension, because of the extension's roughly 120 MB memory limit. Only photos over the cap are scaled, and only down.
- Borders are split evenly: one canvas step up fixes parity, otherwise the image shrinks by one pixel.
- Instagram presets and Square convert to sRGB. Original keeps the source's RGB profile.
- JPEG quality is 0.92.

**Reference results**, which must match the Mac engine at Medium border:

| Source | 4:5 | 3:4 |
|---|---|---|
| 4000 x 6000 | 5120 x 6400 | 4800 x 6400 |
| 6000 x 4000 | 6400 x 8000 | 6144 x 8192 |
| 700 x 1000 | 1080 x 1350 | 1080 x 1440 |

## Screens

1. **Start.** A "Choose photos" button opens `PHPickerViewController` with multi-select, up to 50 photos.
2. **Edit.**
   - A large live preview of the current photo. Swipe to move between selected photos.
   - Segmented controls for Border, Colour and Size. One set of settings applies to the whole batch.
   - Changing a setting re-renders the preview within about 300 ms, debounced.
3. **Saving.** "Save N photos" button, then a progress bar. Photos are processed one at a time to bound memory.
4. **Done.**
   - A thumbnail strip of the saved photos.
   - A list of skipped photos with reasons, if any.
   - "Open Photos" and "Start again" buttons.

## Metadata and privacy

- Kept: TIFF, EXIF, EXIF Aux and IPTC (copyright, camera, lens, capture date). Stale orientation, dimension and colour-space tags are removed.
- Removed: GPS/location, as on the Mac.
- Permission: add-only Photos access (`NSPhotoLibraryAddUsageDescription`). The picker itself needs no permission.
- No network access, accounts, analytics or third-party SDKs that collect data. The App Store privacy label is "Data Not Collected". The privacy policy is a short single page.

## Error handling

- Each photo is processed independently. A failure is recorded as `skipped` with a short reason, and the batch continues.
- Reasons include: not an image, animated or multi-frame, could not download from iCloud, could not render, could not save.
- iCloud-only originals are downloaded by the picker before the edit screen opens, behind a single 'Loading photos…' screen. Photos that fail to load are counted on the start screen.
- If iOS warns about memory during a batch, the current photo finishes and the batch then stops with a "saved N of M" message.
- If Photos permission is refused, the app explains why it is needed and links to Settings.

## Testing

- **Swift unit tests (`RenderPlan`):** every preset and border, the reference table above, the parity rules, the cap, and the no-upscale rule.
- **Swift render tests (simulator):**
  - Exact output dimensions.
  - Equal border widths on opposite edges, checked by sampling pixels.
  - Border colour.
  - GPS removed while EXIF copyright is kept.
  - A Display P3 source converted to sRGB for Instagram presets.
- **Dart tests:** settings state, debounce, and batch progress and error reporting against a fake engine channel.
- **Manual check:** drive the app in the iPhone simulator through every screen and the Share extension before handing over.

## App Store deliverables

- App icon.
- Screenshots for the required iPhone sizes.
- Name, subtitle, description and keywords, written in Tom's voice.
- Privacy policy page.
- A short submission walkthrough, once the Developer Program enrollment is done.

## Out of scope for release 1

- Android.
- iPad-specific layout. The app runs on iPad as a scaled iPhone app.
- Custom colour picker, text or watermark overlays, and cropping.
- Posting directly to Instagram.

## Setup needed before building

- Install Flutter (and CocoaPods if the Flutter version requires it). Neither is on this Mac yet.
- Xcode 27.1 with the iOS 27.1 SDK and simulators is already installed, and its license is accepted.
