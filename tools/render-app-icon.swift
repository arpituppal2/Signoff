#!/usr/bin/env swift
//
// render-app-icon.swift — Procedurally renders the Signoff app icon.
//
//   swift tools/render-app-icon.swift
//
// Produces every PNG in Resources/Assets.xcassets/AppIcon.appiconset at native
// resolution (no downsample blur), plus Resources/AppIcon.icns via iconutil.
//
// Design: a warm-parchment squircle with a calligraphic ink signature flourish
// and an amber ink-drop where the pen lifts — mirroring the in-app "signature"
// SF Symbol and the Ember brand accent. Authored full-bleed per Apple's macOS
// icon grid. Deterministic; no time/random.
//
import AppKit
import Foundation

private enum SignoffIcon {
    // ── Brand palette (warm ink-on-paper + ember accent) ──────────────────
    static let parchmentTop    = NSColor(srgbRed: 1.000, green: 0.984, blue: 0.945, alpha: 1) // #FFFBF1
    static let parchmentBottom = NSColor(srgbRed: 0.949, green: 0.894, blue: 0.788, alpha: 1) // #F2E4C9
    static let parchmentEdge   = NSColor(srgbRed: 0.886, green: 0.824, blue: 0.690, alpha: 1) // #E2D2B0
    static let ink             = NSColor(srgbRed: 0.141, green: 0.102, blue: 0.063, alpha: 1) // #241A10
    static let inkSoft         = NSColor(srgbRed: 0.20,  green: 0.15,  blue: 0.10,  alpha: 1) // highlight blend
    static let ember           = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.024, alpha: 1) // #D97706
    static let emberHi         = NSColor(srgbRed: 0.961, green: 0.620, blue: 0.043, alpha: 1) // #F59E0B

    // Full-bleed squircle; Apple's grid puts design area ~ 0.0–1.0 minus bleed.
    static func draw(in ctx: CGContext, size: CGFloat) {
        let s = size
        // Squircle background, full-bleed. Corner radius tuned to the macOS
        // continuous-corner grid (~22% of canvas).
        let radius = s * 0.220
        let rect = CGRect(x: 0, y: 0, width: s, height: s)
        let path = squirclePath(rect: rect, radius: radius)

        // Vertical parchment gradient (top lighter → bottom warmer).
        let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [parchmentTop.cgColor, parchmentBottom.cgColor] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
        // Soft top-left highlight for paper depth.
        let hi = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [NSColor(white: 1, alpha: 0.45).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(hi,
            startCenter: CGPoint(x: s * 0.32, y: s * 0.78), startRadius: 0,
            endCenter: CGPoint(x: s * 0.32, y: s * 0.78), endRadius: s * 0.62,
            options: [])
        ctx.restoreGState()

        // Inner edge stroke for definition.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(parchmentEdge.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(max(1.5, s * 0.004))
        ctx.strokePath()
        ctx.restoreGState()

        // ── Signature flourish (calligraphic ink stroke) ───────────────────
        // A confident swoop: dips then arcs up to the right, ending in a tail —
        // exactly the gesture of signing off. Centered in the design area.
        let k = s / 1024.0 // geometry authored on a 1024 grid

        // Main signature sweep.
        let sweep = CGMutablePath()
        sweep.move(to: CGPoint(x: 250 * k, y: 412 * k))
        sweep.addCurve(to: CGPoint(x: 482 * k, y: 408 * k),
            control1: CGPoint(x: 346 * k, y: 300 * k),
            control2: CGPoint(x: 430 * k, y: 524 * k))
        sweep.addCurve(to: CGPoint(x: 788 * k, y: 612 * k),
            control1: CGPoint(x: 600 * k, y: 692 * k),
            control2: CGPoint(x: 706 * k, y: 452 * k))

        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // Soft shadow under the ink — grounds the mark on the paper.
        ctx.setShadow(offset: CGSize(width: 0, height: -6 * k),
                      blur: 12 * k,
                      color: NSColor(white: 0.08, alpha: 0.22).cgColor)
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(58 * k)
        ctx.addPath(sweep); ctx.strokePath()
        ctx.restoreGState()

        // Underline flourish (the classic signature underline loop), thinner.
        let underline = CGMutablePath()
        underline.move(to: CGPoint(x: 300 * k, y: 296 * k))
        underline.addCurve(to: CGPoint(x: 660 * k, y: 332 * k),
            control1: CGPoint(x: 430 * k, y: 248 * k),
            control2: CGPoint(x: 560 * k, y: 250 * k))
        underline.addCurve(to: CGPoint(x: 712 * k, y: 410 * k),
            control1: CGPoint(x: 686 * k, y: 360 * k),
            control2: CGPoint(x: 708 * k, y: 384 * k))

        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(ink.withAlphaComponent(0.92).cgColor)
        ctx.setLineWidth(15 * k)
        ctx.addPath(underline); ctx.strokePath()
        ctx.restoreGState()

        // ── Amber ink-drop where the pen lifts off the page ────────────────
        let dropCenter = CGPoint(x: 800 * k, y: 596 * k)
        let dropR = 27 * k
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        // Drop body — ember sphere with a soft shadow to seat it on the paper.
        ctx.setShadow(offset: CGSize(width: 0, height: -4 * k),
                      blur: 9 * k, color: NSColor(white: 0.05, alpha: 0.25).cgColor)
        let dropRect = CGRect(x: dropCenter.x - dropR, y: dropCenter.y - dropR,
                              width: dropR*2, height: dropR*2)
        // Teardrop: circle + small tail toward the sweep's end (788,612).
        let dropPath = CGMutablePath()
        dropPath.addRoundedRect(in: dropRect, cornerWidth: dropR, cornerHeight: dropR)
        // Subtle tail notch by elongating slightly toward the sweep terminus.
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: 788 * k, y: 612 * k))
        tail.addLine(to: dropCenter)
        dropPath.addPath(tail)
        ctx.addPath(dropPath)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // Fill the sphere, then restroke the tail so the teardrop reads.
        ctx.setFillColor(ember.cgColor)
        ctx.fillEllipse(in: dropRect)
        ctx.setStrokeColor(ember.cgColor)
        ctx.setLineWidth(8 * k)
        ctx.addPath(tail); ctx.strokePath()
        ctx.restoreGState()

        // Specular highlight on the drop (the wet-ink sheen).
        ctx.saveGState()
        let sheen = CGRect(x: dropCenter.x - dropR*0.55, y: dropCenter.y + dropR*0.05,
                           width: dropR*0.6, height: dropR*0.35)
        ctx.setFillColor(NSColor(white: 1, alpha: 0.65).cgColor)
        ctx.fillEllipse(in: sheen)
        ctx.restoreGState()
    }

    /// A continuous-corner (squircle) path. We approximate the macOS squircle
    /// with a plain rounded rect at the grid radius — visually equivalent at
    /// icon scale and far simpler/smaller than a true superellipse.
    private static func squirclePath(rect: CGRect, radius: CGFloat) -> CGPath {
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}

private func renderPNG(filename: String, pixels: Int, into dir: URL) {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)! as CGContext?
    else { fatalError("ctx") }
    // Flip so our 0,0-bottom-left geometry matches.
    ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(pixels)))
    SignoffIcon.draw(in: ctx, size: CGFloat(pixels))
    guard let img = ctx.makeImage() else { fatalError("makeImage") }
    let rep = NSBitmapImageRep(cgImage: img)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try! png.write(to: dir.appendingPathComponent(filename))
}

// ── Main ───────────────────────────────────────────────────────────────────
let fm = FileManager.default
let repoRoot = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
let iconset = repoRoot.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// Native-render every declared size (crisper than downsampling).
let sizes: [(file: String, px: Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",  32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",  64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png",256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png",512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png",1024),
    ("icon_1024.png",       1024),
]
for s in sizes { renderPNG(filename: s.file, pixels: s.px, into: iconset) }

// Drop a stray placeholder that's not in Contents.json.
try? fm.removeItem(at: iconset.appendingPathComponent("_master16.png"))

// Author Contents.json with the filenames we wrote.
let contents = """
{
  "images" : [
    {"size":"16x16","filename":"icon_16x16.png","idiom":"mac"},
    {"size":"16x16","filename":"icon_16x16@2x.png","idiom":"mac","scale":"2x"},
    {"size":"32x32","filename":"icon_32x32.png","idiom":"mac"},
    {"size":"32x32","filename":"icon_32x32@2x.png","idiom":"mac","scale":"2x"},
    {"size":"128x128","filename":"icon_128x128.png","idiom":"mac"},
    {"size":"128x128","filename":"icon_128x128@2x.png","idiom":"mac","scale":"2x"},
    {"size":"256x256","filename":"icon_256x256.png","idiom":"mac"},
    {"size":"256x256","filename":"icon_256x256@2x.png","idiom":"mac","scale":"2x"},
    {"size":"512x512","filename":"icon_512x512.png","idiom":"mac"},
    {"size":"512x512","filename":"icon_512x512@2x.png","idiom":"mac","scale":"2x"},
    {"size":"1024x1024","filename":"icon_1024.png","idiom":"mac"}
  ],
  "info" : {"version" : 1, "author" : "Signoff"}
}
"""
try! contents.write(to: iconset.appendingPathComponent("Contents.json"),
                    atomically: true, encoding: .utf8)

// Build a multi-resolution .icns via iconutil into an .iconset scratch dir.
let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("Signoff.iconset", isDirectory: true)
try? fm.removeItem(at: scratch); try! fm.createDirectory(at: scratch, withIntermediateDirectories: true)
// iconutil wants: icon_16x16.png, icon_16x16@2x.png, icon_32x32.png, ... icon_512x512@2x.png
for s in sizes {
    try? fm.copyItem(at: iconset.appendingPathComponent(s.file),
                     to: scratch.appendingPathComponent(s.file))
}
let icns = repoRoot.appendingPathComponent("Resources/AppIcon.icns")
let p = Process(); p.launchPath = "/usr/bin/iconutil"
p.arguments = ["-c", "icns", scratch.path, "-o", icns.path]
try? p.run(); p.waitUntilExit()
print("✅ Rendered \(sizes.count) PNGs + AppIcon.icns")
print("   \(iconset.path)")
print("   \(icns.path)")
