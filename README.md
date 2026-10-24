# BorderMe

You've got a photo you like and you want it sitting on clean white, ready to post. BorderMe does that from Finder's right-click menu: select your images, pick a border, pick a size, and it writes new JPEGs beside the originals. Your originals are never touched.

It's a macOS Quick Action, so there's no app to open and nothing running in the background.

## Install

You need macOS 11 (Big Sur) or later. Works on both Apple silicon and Intel Macs.

1. Download this repository (green **Code** button, then **Download ZIP**) and unzip it.
2. Open Terminal, type `cd ` and drag the unzipped folder onto the Terminal window, then press Return.
3. Run:

   ```bash
   ./install.sh
   ```

That's it. The installer copies the Quick Action into `~/Library/Services`, clears the quarantine flag macOS puts on anything downloaded from the internet, and tells Finder to pick it up.

If BorderMe doesn't show up in the right-click menu straight away, enable it in **System Settings > General > Login Items & Extensions > Finder extensions**, or just log out and back in.

To remove it later:

```bash
./install.sh --uninstall
```

### Why the Terminal step

BorderMe isn't signed with an Apple Developer certificate, because those cost money and this is a small free thing. Without one, macOS quarantines the download and refuses to run the little image engine inside. `install.sh` clears that flag on a copy you've chosen to install yourself. You can drag the bundle into `~/Library/Services` by hand instead if you'd rather, and BorderMe will show you the exact command to run when it hits the block.

## Use

1. Select one or more images in Finder.
2. Right-click and choose **Quick Actions > BorderMe**.
3. Choose **Small**, **Medium**, or **Large** border thickness.
4. Choose a standard output size or an Instagram preset.

New files are saved beside the originals, named after the source with the border and size on the end. Nothing is overwritten; a second run adds a number.

## Presets

- Border: Small 2%, Medium 5%, Large 8%, measured against the photo's shorter edge.
- Standard output: Small up to 1200 px, Medium up to 2400 px, Large keeps the original resolution.
- Instagram Portrait: exactly 4:5 (the 1080 x 1350 shape). Works everywhere, including scheduling tools.
- Instagram Tall: exactly 3:4 (the 1080 x 1440 shape). The taller format, native when you post from the Instagram app.
- Instagram Landscape: exactly 1.91:1.

The Instagram presets place your complete uncropped photo in the centre of an exact-ratio canvas, so nothing gets chopped off. The canvas is built around your photo at its full resolution rather than squeezed down to 1080 px, so you upload as much detail as you have and Instagram does its one resize from there. Side and top borders will differ when your photo's shape doesn't match the canvas, and that's the trade for keeping the whole frame. Very large photos are brought down to roughly 8192 px on the long edge, which is still far more than Instagram shows.

One thing worth knowing: BorderMe never enlarges a photo. Feed a small image into an Instagram preset and it sits at its native size in a canvas at least 1080 px wide, with more white around it than the percentage you picked. Better that than a soft, upscaled photo.

## What happens to your metadata

Copyright, camera, lens, and capture date all carry across to the new file, so your bordered copy is still yours and still says so.

Location data does not. These files are made to be posted, and GPS coordinates are rarely something you meant to publish along with the picture. If you need the coordinates, they're still sitting in your original.

Colour profiles are kept as they are, so a Display P3 photo stays Display P3 and its most saturated colours survive. The two Instagram presets are the exception: those convert to sRGB, because that's what Instagram expects.

## Supported files

Anything macOS can read as a single-frame image: JPEG, HEIC, PNG, TIFF, most camera raw files. Transparent areas in a PNG come out white. Animated GIFs and multi-page files are skipped, and BorderMe tells you which ones it skipped and why.

Output is always JPEG.

## Building from source

The compiled engine is committed so you don't need Xcode just to use this. If you want to change it, edit `BorderMe.workflow/Contents/Resources/BorderMe.swift` and run:

```bash
./build.sh
```

That compiles both architectures, joins them into a universal binary, and signs it ad-hoc. You'll need the Xcode command line tools (`xcode-select --install`).

The shell driver at `BorderMe.workflow/Contents/Resources/borderme.sh` reads a few environment variables, which makes it easy to test without clicking through dialogs:

```bash
BORDERME_NO_NOTIFY=1 BORDERME_BORDER=medium BORDERME_OUTPUT=small ./borderme.sh photo.jpg
```

`BORDERME_BORDER` takes `small`, `medium`, or `large`. `BORDERME_OUTPUT` takes those plus `instagram-portrait`, `instagram-tall`, and `instagram-landscape`. `BORDERME_ENGINE` points at a different engine binary if you're testing one.

## Licence

MIT, which is about as permissive as it gets. Use it, change it, build it into something of your own, sell that something if you like. Just keep the copyright line in `LICENSE` with it, and know that it comes with no warranty from me.

## Thanks

If you use this and something breaks, or a preset you want is missing, open an issue and tell me about it.
