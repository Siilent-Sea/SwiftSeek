// Generate SwiftSeek app icon (.iconset PNGs + optional direct .icns).
//
// Usage:
//   swift scripts/make-icon.swift /tmp/AppIcon.iconset
//       — emit only the 10 .iconset PNGs (legacy iconutil flow)
//   swift scripts/make-icon.swift /tmp/AppIcon.iconset --icns /path/AppIcon.icns
//       — also assemble an .icns directly without iconutil
//
// Round 3 fix: K2 round 1/2 hit "Invalid Iconset" from `iconutil`
// despite all PNG dimensions being correct. Codex sandbox iconutil
// rejects what local iconutil accepts (toolchain version drift).
// Direct .icns assembly bypasses iconutil entirely; the .icns
// binary format is documented and we already have all 10 PNGs in
// memory.

import AppKit
import Foundation

let argv = CommandLine.arguments
guard argv.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out-iconset-dir> [--icns <out-icns-path>]\n".utf8))
    exit(2)
}
let outDir = argv[1]

// Optional --icns flag for direct .icns output.
var icnsPath: String? = nil
var i = 2
while i < argv.count {
    let a = argv[i]
    if a == "--icns" {
        i += 1
        guard i < argv.count else {
            FileHandle.standardError.write(Data("--icns requires a path arg\n".utf8))
            exit(2)
        }
        icnsPath = argv[i]
    } else {
        FileHandle.standardError.write(Data("unknown arg: \(a)\n".utf8))
        exit(2)
    }
    i += 1
}

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
    // Round 2 fix: build the NSBitmapImageRep explicitly at the
    // requested pixel size, NOT via NSImage.lockFocus(). The latter
    // produced PNGs whose pixel dimensions varied with the running
    // display's backing scale (e.g. icon_16x16.png coming out as
    // 32×32 on @2x screens). iconutil strictly validates that
    // pixel dimensions match the filename declaration; mismatches
    // cause the whole iconset to fail with "Invalid Iconset".
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    // Force points == pixels so the drawing context maps 1:1 with
    // the requested pixel grid.
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)

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
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setLineWidth(stroke)

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

    return rep.representation(using: .png, properties: [:])
}

// Cache rendered PNG data per pixel size so the .icns assembler
// doesn't re-render the same size twice (e.g. 32 appears as both
// icon_16x16@2x and icon_32x32).
var pngBySize: [Int: Data] = [:]
for spec in specs {
    let data: Data
    if let cached = pngBySize[spec.pixels] {
        data = cached
    } else {
        guard let rendered = renderIcon(pixels: spec.pixels) else {
            FileHandle.standardError.write(Data("failed: \(spec.name)\n".utf8))
            exit(1)
        }
        data = rendered
        pngBySize[spec.pixels] = rendered
    }
    let path = (outDir as NSString).appendingPathComponent(spec.name)
    try data.write(to: URL(fileURLWithPath: path))
    print("wrote \(spec.name) (\(spec.pixels)px) \(data.count) bytes")
}
print("done — \(specs.count) PNGs in \(outDir)")

// --- Round 3: direct .icns assembly --------------------------------------
//
// Apple .icns container format (documented at
// https://en.wikipedia.org/wiki/Apple_Icon_Image_format and Apple
// Developer archive). Layout:
//
//   File header:
//     4 bytes  magic = "icns"
//     4 bytes  total file size in bytes (big-endian uint32),
//              including this 8-byte header.
//   Repeated entries:
//     4 bytes  OSType code (e.g. "ic07" for 128x128 PNG)
//     4 bytes  entry length including this 8-byte header (BE uint32)
//     N bytes  payload (PNG data for modern entries)
//
// OSType -> pixel size mapping for PNG entries:
//   ic04  16x16
//   ic05  32x32
//   ic07  128x128
//   ic08  256x256
//   ic09  512x512
//   ic10  1024x1024 (also accepted as 512@2x source)
//   ic11  16x16@2x   (32x32 PNG, marked as retina)
//   ic12  32x32@2x   (64x64 PNG, retina)
//   ic13  128x128@2x (256x256 PNG, retina)
//   ic14  256x256@2x (512x512 PNG, retina)
//
// We emit all 10 to maximize the chance Finder / Dock pick a sharp
// representation at every display scale.
if let icnsOut = icnsPath {
    struct IcnsEntry { let type: String; let pixels: Int }
    let icnsEntries: [IcnsEntry] = [
        IcnsEntry(type: "ic04", pixels: 16),
        IcnsEntry(type: "ic05", pixels: 32),
        IcnsEntry(type: "ic07", pixels: 128),
        IcnsEntry(type: "ic08", pixels: 256),
        IcnsEntry(type: "ic09", pixels: 512),
        IcnsEntry(type: "ic10", pixels: 1024),
        IcnsEntry(type: "ic11", pixels: 32),
        IcnsEntry(type: "ic12", pixels: 64),
        IcnsEntry(type: "ic13", pixels: 256),
        IcnsEntry(type: "ic14", pixels: 512),
    ]

    /// Big-endian UInt32 -> 4-byte Data.
    func be32(_ value: UInt32) -> Data {
        var v = value.bigEndian
        return withUnsafeBytes(of: &v) { Data($0) }
    }

    var body = Data()
    for entry in icnsEntries {
        guard let png = pngBySize[entry.pixels] else {
            FileHandle.standardError.write(Data("missing PNG for \(entry.type) (\(entry.pixels)px)\n".utf8))
            exit(1)
        }
        guard let typeBytes = entry.type.data(using: .ascii), typeBytes.count == 4 else {
            FileHandle.standardError.write(Data("bad OSType: \(entry.type)\n".utf8))
            exit(1)
        }
        body.append(typeBytes)
        body.append(be32(UInt32(8 + png.count))) // 8-byte header + payload
        body.append(png)
    }

    var file = Data()
    file.append("icns".data(using: .ascii)!)
    file.append(be32(UInt32(8 + body.count)))
    file.append(body)

    try file.write(to: URL(fileURLWithPath: icnsOut))
    print("wrote \(icnsOut) (\(file.count) bytes, \(icnsEntries.count) entries)")
}
