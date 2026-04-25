// Generate SwiftSeek app icon (.iconset PNGs).
//
// Usage:
//   swift scripts/make-icon.swift /tmp/AppIcon.iconset
//   iconutil -c icns -o SwiftSeek.app/Contents/Resources/AppIcon.icns /tmp/AppIcon.iconset
//
// Renders a rounded-square gradient background with a centered
// SF Symbol "magnifyingglass" glyph in white. All required Apple
// .iconset sizes generated (16-1024 + @2x).

import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out-iconset-dir>\n".utf8))
    exit(2)
}
let outDir = CommandLine.arguments[1]
let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Apple .iconset names: icon_<size>x<size>[@2x].png
struct Spec { let pixels: Int; let name: String }
let specs: [Spec] = [
    Spec(pixels:   16, name: "icon_16x16.png"),
    Spec(pixels:   32, name: "icon_16x16@2x.png"),
    Spec(pixels:   32, name: "icon_32x32.png"),
    Spec(pixels:   64, name: "icon_32x32@2x.png"),
    Spec(pixels:  128, name: "icon_128x128.png"),
    Spec(pixels:  256, name: "icon_128x128@2x.png"),
    Spec(pixels:  256, name: "icon_256x256.png"),
    Spec(pixels:  512, name: "icon_256x256@2x.png"),
    Spec(pixels:  512, name: "icon_512x512.png"),
    Spec(pixels: 1024, name: "icon_512x512@2x.png"),
]

func renderIcon(pixels: Int) -> Data? {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }
    let rect = NSRect(origin: .zero, size: size)

    // Rounded-square background with vertical gradient (deep blue -> teal).
    // macOS Big Sur+ icons use a 22.37% corner radius of side length.
    let cornerRadius = CGFloat(pixels) * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()

    let top = NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.85, alpha: 1.0)
    let bot = NSColor(calibratedRed: 0.05, green: 0.65, blue: 0.75, alpha: 1.0)
    let gradient = NSGradient(starting: top, ending: bot)!
    gradient.draw(in: rect, angle: -90)

    // Magnifying glass glyph drawn manually so it renders the same
    // way down to 16px. Geometry expressed as fractions of side.
    let s = CGFloat(pixels)
    let lensCenter = CGPoint(x: s * 0.42, y: s * 0.58)
    let lensRadius = s * 0.22
    let stroke = max(s * 0.07, 1.5)
    let handleStart = CGPoint(x: lensCenter.x + lensRadius * 0.7071,
                              y: lensCenter.y - lensRadius * 0.7071)
    let handleEnd = CGPoint(x: handleStart.x + s * 0.20,
                            y: handleStart.y - s * 0.20)

    NSColor.white.setStroke()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(stroke)

    // Lens (open ring, transparent fill).
    let ring = NSBezierPath(ovalIn: NSRect(x: lensCenter.x - lensRadius,
                                           y: lensCenter.y - lensRadius,
                                           width: lensRadius * 2,
                                           height: lensRadius * 2))
    ring.lineWidth = stroke
    ring.stroke()

    // Handle.
    let handle = NSBezierPath()
    handle.move(to: handleStart)
    handle.line(to: handleEnd)
    handle.lineWidth = stroke
    handle.lineCapStyle = .round
    handle.stroke()

    image.unlockFocus()

    // PNG from rep.
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

for spec in specs {
    guard let data = renderIcon(pixels: spec.pixels) else {
        FileHandle.standardError.write(Data("failed: \(spec.name)\n".utf8))
        exit(1)
    }
    let path = (outDir as NSString).appendingPathComponent(spec.name)
    try data.write(to: URL(fileURLWithPath: path))
    print("wrote \(spec.name) (\(spec.pixels)px) \(data.count) bytes")
}
print("done — \(specs.count) PNGs in \(outDir)")
