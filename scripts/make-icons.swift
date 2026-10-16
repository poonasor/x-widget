#!/usr/bin/env swift
// Regenerates the app icon and menu bar icon in XWidget/Assets.xcassets.
// The mark is an original bold "X" set in SF Pro Black, not X Corp's trademarked logo.
// Usage: swift scripts/make-icons.swift
import AppKit

// Resolve the repo root from this script's own location (absolute, symlinks resolved),
// so it works no matter which directory it's run from or how the path was typed.
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let repoRoot = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: cwd)
    .absoluteURL.standardizedFileURL.resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent()
guard FileManager.default.fileExists(atPath: repoRoot.appending(path: "project.yml").path) else {
    fatalError("Couldn't find project.yml in \(repoRoot.path). Run this script from the X Widget repo.")
}
let assets = repoRoot.appending(path: "XWidget/Assets.xcassets")

func png(size: Int, draw: (CGContext, CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext, CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func line(_ fontSize: CGFloat, color: NSColor) -> CTLine {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
    return CTLineCreateWithAttributedString(NSAttributedString(string: "X", attributes: [.font: font, .foregroundColor: color]))
}

/// Draws a heavy "X" whose glyph is exactly `fraction` of `rect`'s height, centred on its glyph bounds (not line height).
func drawX(in rect: CGRect, fraction: CGFloat, color: NSColor, context: CGContext) {
    // Glyph height scales linearly with font size, so measure once at a reference size and scale.
    let reference: CGFloat = 100
    let referenceHeight = CTLineGetBoundsWithOptions(line(reference, color: color), .useGlyphPathBounds).height
    let line = line(reference * rect.height * fraction / referenceHeight, color: color)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.textPosition = CGPoint(x: rect.midX - bounds.midX, y: rect.midY - bounds.midY)
    CTLineDraw(line, context)
}

func write(_ data: Data, _ path: String) throws {
    let url = assets.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

// MARK: App icon — macOS icon grid: 824pt rounded tile inside a 1024pt canvas.

func appIcon(_ size: Int) -> Data {
    png(size: size) { ctx, s in
        let scale = s / 1024
        let tile = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
        let path = CGPath(roundedRect: tile, cornerWidth: 185 * scale, cornerHeight: 185 * scale, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [NSColor(white: 0.20, alpha: 1).cgColor, NSColor(white: 0.03, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
        ctx.restoreGState()

        drawX(in: tile, fraction: 0.52, color: .white, context: ctx)
    }
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try write(appIcon(points * scale), "AppIcon.appiconset/\(name)")
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let appIconContents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try write(try JSONSerialization.data(withJSONObject: appIconContents, options: [.prettyPrinted, .sortedKeys]), "AppIcon.appiconset/Contents.json")

// MARK: Menu bar icon — a template image, so macOS tints it for light/dark menu bars.

for scale in [1, 2] {
    let data = png(size: 18 * scale) { ctx, s in
        drawX(in: CGRect(x: 0, y: 0, width: s, height: s), fraction: 0.73, color: .black, context: ctx)
    }
    try write(data, "MenuBarIcon.imageset/menubar\(scale == 2 ? "@2x" : "").png")
}
let menuContents: [String: Any] = [
    "images": [
        ["idiom": "universal", "scale": "1x", "filename": "menubar.png"],
        ["idiom": "universal", "scale": "2x", "filename": "menubar@2x.png"],
    ],
    "info": ["author": "xcode", "version": 1],
    "properties": ["template-rendering-intent": "template"],
]
try write(try JSONSerialization.data(withJSONObject: menuContents, options: [.prettyPrinted, .sortedKeys]), "MenuBarIcon.imageset/Contents.json")

try write(Data(#"{"info":{"author":"xcode","version":1}}"#.utf8), "Contents.json")
print("✓ Icons written to \(assets.path)")
