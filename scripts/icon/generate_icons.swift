#!/usr/bin/env swift
//
// Source of truth for the Upmarket app icon and menu bar glyph.
//
// Draws a rounded `#`, applies a real Y-axis perspective rotation (the hash
// swings like a door — left edge forward), then emits:
//   * AppIcon PNGs (16…1024) — amber squircle + specular highlight + white hash
//   * MenuBarHash template PNGs (1x/2x) — monochrome hash on transparent
//
// Run: swift scripts/icon/generate_icons.swift
//
// There is intentionally no SVG source: a Y-axis perspective is non-affine and
// cannot be expressed as a single SVG matrix, so this generator is canonical.

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Design constants

let yAxisDegrees: CGFloat = 35          // door-swing angle
let perspectiveDistance: CGFloat = 2.4  // smaller = stronger foreshortening
let leftEdgeForward = true              // left edge nearer the viewer

let squircleRadiusRatio: CGFloat = 0.215
let gradientAngle: CGFloat = -59        // top-left (light) -> bottom-right (dark)
let gradientStops: [(CGFloat, NSColor)] = [
    (0.0, NSColor(srgbRed: 1.00, green: 0.753, blue: 0.251, alpha: 1)), // #FFC040
    (0.5, NSColor(srgbRed: 0.910, green: 0.471, blue: 0.0, alpha: 1)),  // #E87800
    (1.0, NSColor(srgbRed: 0.910, green: 0.431, blue: 0.0, alpha: 1)),  // #E86E00
]

let master: CGFloat = 1024              // hash is rendered/warped at this resolution

// MARK: - Paths

let projectRoot = FileManager.default.currentDirectoryPath
let appIconDir = "\(projectRoot)/Upmarket/Upmarket/Assets.xcassets/AppIcon.appiconset"
let menuBarDir = "\(projectRoot)/Upmarket/Upmarket/Assets.xcassets/MenuBarHash.imageset"

// MARK: - Hash glyph

/// Render the rounded `#` (round-capped strokes) into a square bitmap.
func renderHash(size M: CGFloat, color: NSColor) -> CGImage {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(M), pixelsHigh: Int(M),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // The hash fills almost the whole bitmap so the Y-axis perspective (applied
    // to the full square below) reaches the glyph's left/right extremities.
    color.setStroke()
    let thickness = M * 0.115
    let pad = M * 0.08
    let lo = pad, hi = M - pad
    let v1 = M * 0.36, v2 = M * 0.64     // vertical bars
    let h1 = M * 0.36, h2 = M * 0.64     // horizontal bars

    func bar(_ a: NSPoint, _ b: NSPoint) {
        let p = NSBezierPath()
        p.lineWidth = thickness
        p.lineCapStyle = .round
        p.move(to: a)
        p.line(to: b)
        p.stroke()
    }
    bar(NSPoint(x: v1, y: lo), NSPoint(x: v1, y: hi))
    bar(NSPoint(x: v2, y: lo), NSPoint(x: v2, y: hi))
    bar(NSPoint(x: lo, y: h1), NSPoint(x: hi, y: h1))
    bar(NSPoint(x: lo, y: h2), NSPoint(x: hi, y: h2))

    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

// MARK: - Y-axis perspective

/// Project the four corners of a flat quad rotated about the Y axis, then fit
/// the result into a `box`-sized square with `pad` margin. Returns CI points
/// (y-up) for top-left, top-right, bottom-right, bottom-left.
func perspectiveCorners(box: CGFloat, pad: CGFloat)
    -> (tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint) {
    let theta = yAxisDegrees * .pi / 180 * (leftEdgeForward ? 1 : -1)
    let d = perspectiveDistance

    func proj(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let xp = x * cos(theta)
        let zp = -x * sin(theta)           // +z toward viewer
        let f = d / (d - zp)               // perspective scale
        return CGPoint(x: xp * f, y: y * f)
    }
    // Normalized corners, y-up: tl, tr, br, bl
    let raw = [proj(-1, 1), proj(1, 1), proj(1, -1), proj(-1, -1)]
    let xs = raw.map(\.x), ys = raw.map(\.y)
    let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
    let w = maxX - minX, h = maxY - minY
    let s = (box - 2 * pad) / max(w, h)
    let offX = (box - w * s) / 2, offY = (box - h * s) / 2
    func map(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - minX) * s + offX, y: (p.y - minY) * s + offY)
    }
    return (map(raw[0]), map(raw[1]), map(raw[2]), map(raw[3]))
}

/// Warp a square hash bitmap into a `box`-sized perspective image.
func warpedHash(color: NSColor, box: CGFloat, pad: CGFloat) -> CGImage {
    let hash = renderHash(size: master, color: color)
    let ci = CIImage(cgImage: hash)
    // Scale input to the target box first so corner coordinates line up.
    let scaled = ci.transformed(by: CGAffineTransform(scaleX: box / master, y: box / master))

    let c = perspectiveCorners(box: box, pad: pad)
    let filter = CIFilter.perspectiveTransform()
    filter.inputImage = scaled
    filter.topLeft = c.tl
    filter.topRight = c.tr
    filter.bottomRight = c.br
    filter.bottomLeft = c.bl

    let ctx = CIContext(options: [.useSoftwareRenderer: true])
    let out = filter.outputImage!
    return ctx.createCGImage(out, from: CGRect(x: 0, y: 0, width: box, height: box))!
}

// MARK: - Compositing

func writePNG(_ image: NSImage, pixels: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(pixels), pixelsHigh: Int(pixels),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// Pre-warp the hash once at high resolution; scale down per icon size.
let dockHashCG = warpedHash(color: .white, box: master, pad: master * 0.085)
let dockHashImage = NSImage(cgImage: dockHashCG, size: NSSize(width: master, height: master))

func dockIcon(size S: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: S, height: S))
    image.lockFocus()

    // Squircle background
    let rect = NSRect(x: 0, y: 0, width: S, height: S)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: S * squircleRadiusRatio,
                                yRadius: S * squircleRadiusRatio)
    let gradient = NSGradient(
        colors: gradientStops.map(\.1),
        atLocations: gradientStops.map(\.0), colorSpace: .sRGB
    )!
    gradient.draw(in: squircle, angle: gradientAngle)

    // Specular highlight
    NSColor(white: 1, alpha: 0.10).setFill()
    NSBezierPath(ovalIn: NSRect(x: S * 0.227, y: S * 0.785, width: S * 0.546, height: S * 0.196)).fill()

    // Perspective hash with drop shadow
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.478, green: 0.227, blue: 0, alpha: 0.30)
    shadow.shadowOffset = NSSize(width: 0, height: -S * 0.0078)
    shadow.shadowBlurRadius = S * 0.0176
    shadow.set()
    let hashSide = S * 0.82
    let hashRect = NSRect(x: (S - hashSide) / 2, y: (S - hashSide) / 2, width: hashSide, height: hashSide)
    dockHashImage.draw(in: hashRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    image.unlockFocus()
    return image
}

// MARK: - Emit AppIcon

let dockSizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
for size in dockSizes {
    let icon = dockIcon(size: size)
    writePNG(icon, pixels: size, to: "\(appIconDir)/icon_\(Int(size)).png")
    print("wrote icon_\(Int(size)).png")
}

// MARK: - Emit MenuBarHash template (monochrome, transparent)

func menuBarTemplate(pixels: CGFloat) -> NSImage {
    let cg = warpedHash(color: .black, box: pixels, pad: pixels * 0.06)
    return NSImage(cgImage: cg, size: NSSize(width: pixels, height: pixels))
}
writePNG(menuBarTemplate(pixels: 36), pixels: 18, to: "\(menuBarDir)/menubar_hash.png")
writePNG(menuBarTemplate(pixels: 72), pixels: 36, to: "\(menuBarDir)/menubar_hash@2x.png")
print("wrote MenuBarHash template (1x/2x)")
