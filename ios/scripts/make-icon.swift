// Draws the app icon: three shrinking bars (the filter glyph the Filters tab
// uses) on a near-black ground. Run from ios/ with:
//   swift scripts/make-icon.swift
import AppKit
import CoreGraphics

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// No alpha channel: App Store Connect rejects icons that have one.
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: Int) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

context.setFillColor(color(0x0B0E11))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Widest bar at the top, narrowest at the bottom, all centred.
let widths: [CGFloat] = [620, 440, 260]
let height: CGFloat = 96
let gap: CGFloat = 96
let total = CGFloat(widths.count) * height + CGFloat(widths.count - 1) * gap
var y = (CGFloat(size) + total) / 2 - height
for width in widths {
    let rect = CGRect(x: (CGFloat(size) - width) / 2, y: y, width: width, height: height)
    context.setFillColor(color(0xF5F5F5))
    context.addPath(CGPath(roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
    context.fillPath()
    y -= height + gap
}

let image = NSBitmapImageRep(cgImage: context.makeImage()!)
let png = image.representation(using: .png, properties: [:])!
let out = URL(fileURLWithPath: "D4NSocial/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
try! png.write(to: out)
print("wrote \(out.path)")
