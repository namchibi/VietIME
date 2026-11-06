// Builds VietIME's app icon from Icon/source.png (yellow "VI" + star on red).
// Run from the repo root:  swift Icon/make-icon.swift
// Writes Icon/AppIcon.png (1024 px preview) and Icon/AppIcon.icns.
//
// The source art has a ragged, speckled edge around its rounded square, so it is
// cropped just inside that edge, clipped to a clean rounded square, and placed on
// Apple's icon grid (an 824 pt body on a 1024 pt canvas) with a soft shadow.
import AppKit

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 230

/// The rounded square inside source.png, in pixels from the top-left, inset a
/// little so the fringe falls outside it.
let crop = CGRect(x: 82, y: 105, width: 1071, height: 1066)

let source = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: "Icon/source.png")))!
let art = source.cgImage!.cropping(to: crop)!

func draw(_ ctx: CGContext) {
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft drop shadow under the whole icon.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.30))
    ctx.addPath(path); ctx.setFillColor(CGColor(srgbRed: 0.6, green: 0, blue: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(art, in: body)
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    gc.cgContext.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw(gc.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "Icon")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(size: 1024).write(to: dir.appendingPathComponent("AppIcon.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
try p.run(); p.waitUntilExit()
guard p.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Icon/AppIcon.png and Icon/AppIcon.icns")
