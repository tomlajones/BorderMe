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
