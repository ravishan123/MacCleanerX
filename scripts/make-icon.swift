#!/usr/bin/env swift
// Draws the Mac Cleaner app icon with CoreGraphics and writes every size the
// asset catalog needs, plus images for the README and the download page:
// icon.png, banner-{dark,light}.png (from the .svg banners) and social-preview.png.
//
// Usage: swift scripts/make-icon.swift      (run from the repository root)
//
// Design: a dark "Mono" squircle with a ring of 60 dots that sweeps clockwise
// like a scan in progress (dim → white, with a red leading dot), and a white
// sparkle in the middle for "clean".

import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appending(path: "App/MacCleaner/Resources/Assets.xcassets/AppIcon.appiconset")
let images = root.appending(path: "docs/images")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Four-pointed star centred at `c`, outer radius `r`, waist `w` (0…1).
func sparkle(_ c: CGPoint, _ r: CGFloat, waist w: CGFloat = 0.16) -> CGPath {
    let p = CGMutablePath()
    let pts = [CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x + r, y: c.y),
               CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x - r, y: c.y)]
    p.move(to: pts[0])
    for i in 0..<4 {
        let a = pts[i], b = pts[(i + 1) % 4]
        // Control point pulled towards the centre makes the concave sides.
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let ctrl = CGPoint(x: c.x + (mid.x - c.x) * w * 2, y: c.y + (mid.y - c.y) * w * 2)
        p.addQuadCurve(to: b, control: ctrl)
    }
    p.closeSubpath()
    return p
}

/// Draws the icon into a square context of side `s` (in pixels).
func drawIcon(_ ctx: CGContext, _ s: CGFloat) {
    let k = s / 1024                              // design is on a 1024 grid
    // Apple macOS grid: 824 pt body centred, room for the drop shadow.
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = CGPath(roundedRect: body, cornerWidth: 186 * k, cornerHeight: 186 * k, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 28 * k, color: color(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(color(0x111113)); ctx.fillPath()
    ctx.restoreGState()

    // Body gradient
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [color(0x34343A), color(0x161618), color(0x0A0A0B)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // Soft glow behind the centre
    let centre = CGPoint(x: 512 * k, y: 512 * k)
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(0xFFFFFF, 0.14), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 300 * k, options: [])
    ctx.restoreGState()

    // Hairline highlight on the top edge
    ctx.saveGState()
    ctx.addPath(shape); ctx.setStrokeColor(color(0xFFFFFF, 0.10)); ctx.setLineWidth(3 * k); ctx.strokePath()
    ctx.restoreGState()

    // Ring of dots: a clockwise sweep from 12 o'clock, ~78% complete.
    let count = 60, ringR = 312 * k, sweep = 0.78
    let head = Int(Double(count) * sweep)
    for i in 0..<count {
        let angle = CGFloat.pi / 2 - CGFloat(i) / CGFloat(count) * 2 * .pi
        let p = CGPoint(x: centre.x + cos(angle) * ringR, y: centre.y + sin(angle) * ringR)
        var r = 11 * k
        let fill: CGColor
        if i == head {
            r = 19 * k
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 30 * k, color: color(0xFF2D37, 0.9))
            ctx.setFillColor(color(0xE8202B))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            ctx.restoreGState()
            continue
        } else if i < head {
            let t = CGFloat(i) / CGFloat(head)            // 0 → 1 along the trail
            fill = color(0xFFFFFF, 0.30 + 0.70 * t)
            r = (8 + 4 * t) * k
        } else {
            fill = color(0xFFFFFF, 0.13)
            r = 8 * k
        }
        ctx.setFillColor(fill)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }

    // Sparkles
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40 * k, color: color(0xFFFFFF, 0.45))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.addPath(sparkle(CGPoint(x: 490 * k, y: 490 * k), 188 * k)); ctx.fillPath()
    ctx.addPath(sparkle(CGPoint(x: 640 * k, y: 645 * k), 64 * k)); ctx.fillPath()
    ctx.setFillColor(color(0xFFFFFF, 0.75))
    ctx.addPath(sparkle(CGPoint(x: 372 * k, y: 660 * k), 34 * k)); ctx.fillPath()
    ctx.restoreGState()
}

func render(width: Int, height: Int, _ draw: (CGContext) -> Void) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
    print("wrote", url.path.replacingOccurrences(of: root.path + "/", with: ""))
}

// App icon sizes (filenames already referenced by Contents.json)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    write(render(width: px, height: px) { drawIcon($0, CGFloat(px)) }, iconSet.appending(path: "icon_\(px).png"))
}

// README / website icon
write(render(width: 512, height: 512) { drawIcon($0, 512) }, images.appending(path: "icon.png"))

// Banner PNGs (2x) for places that can't show SVG: release notes, social cards.
func loadBanner(_ name: String) -> CGImage {
    let url = images.appending(path: "banner-\(name).svg")
    // AppKit's SVG renderer doesn't know "ui-monospace", so name Menlo explicitly.
    let svg = try! String(contentsOf: url, encoding: .utf8)
        .replacingOccurrences(of: "font-family=\"ui-monospace,", with: "font-family=\"Menlo, ui-monospace,")
    guard let img = NSImage(data: Data(svg.utf8)) else { fatalError("can't read \(url.path)") }
    var rect = CGRect(x: 0, y: 0, width: 2560, height: 800)
    return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
}
for name in ["dark", "light"] {
    let banner = loadBanner(name)
    write(render(width: 2560, height: 800) { $0.draw(banner, in: CGRect(x: 0, y: 0, width: 2560, height: 800)) },
          images.appending(path: "banner-\(name).png"))
}

// Social preview (GitHub → Settings → Social preview), 1280×640: the dark banner on black.
let dark = loadBanner("dark")
write(render(width: 1280, height: 640) { ctx in
    ctx.setFillColor(color(0x000000)); ctx.fill(CGRect(x: 0, y: 0, width: 1280, height: 640))
    ctx.draw(dark, in: CGRect(x: 0, y: 120, width: 1280, height: 400))
}, images.appending(path: "social-preview.png"))
