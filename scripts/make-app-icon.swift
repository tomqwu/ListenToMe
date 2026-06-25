#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Renders a 1024x1024 master app icon (indigo->purple vertical gradient rounded square with a
// centered white "waveform" SF Symbol) and writes every macOS app-icon size, plus a matching
// Contents.json, into App/Assets.xcassets/AppIcon.appiconset/. Run: swift scripts/make-app-icon.swift

let master: CGFloat = 1024

func renderMaster() -> NSImage {
    let image = NSImage(size: NSSize(width: master, height: master))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: master, height: master)
    // macOS icon grid: a rounded square inset slightly from the canvas edges.
    let inset: CGFloat = master * 0.08
    let bgRect = rect.insetBy(dx: inset, dy: inset)
    let radius = bgRect.width * 0.235   // ~ the macOS continuous-corner squircle proportion
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius,
                        transform: nil)

    // Indigo -> purple vertical gradient.
    let top = CGColor(red: 0.42, green: 0.36, blue: 0.95, alpha: 1)
    let bottom = CGColor(red: 0.62, green: 0.30, blue: 0.86, alpha: 1)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray,
                                    locations: [0, 1]) else {
        image.unlockFocus()
        return image
    }

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    // y grows upward in this context, so draw from the top edge down for "top" -> "bottom".
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: bgRect.midX, y: bgRect.maxY),
                           end: CGPoint(x: bgRect.midX, y: bgRect.minY),
                           options: [])
    ctx.restoreGState()

    // Centered white SF Symbol, ~55% of the canvas. Render the symbol with a white palette so
    // the glyph itself is white (drawing a template image directly would paint it black).
    let symbolSide = master * 0.55
    let config = NSImage.SymbolConfiguration(pointSize: symbolSide, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let base = NSImage(systemSymbolName: "waveform", accessibilityDescription: "ListenToMe"),
       let symbol = base.withSymbolConfiguration(config) {
        symbol.isTemplate = false
        let drawn = symbol.size
        let scale = min(symbolSide / drawn.width, symbolSide / drawn.height)
        let size = CGSize(width: drawn.width * scale, height: drawn.height * scale)
        let origin = CGPoint(x: (master - size.width) / 2, y: (master - size.height) / 2)
        let symbolRect = CGRect(origin: origin, size: size)
        symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

func pngData(from image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// (base point size, scale) for the macOS app icon set.
let variants: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2),
    (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

let fm = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let repoRoot = scriptURL.deletingLastPathComponent()
let assetsDir = repoRoot
    .appendingPathComponent("App/Assets.xcassets", isDirectory: true)
let iconSetDir = assetsDir
    .appendingPathComponent("AppIcon.appiconset", isDirectory: true)
try? fm.createDirectory(at: iconSetDir, withIntermediateDirectories: true)

let masterImage = renderMaster()

struct Entry {
    let idiom = "mac"
    let size: Int
    let scale: Int
    var filename: String { "icon_\(size)x\(size)@\(scale)x.png" }
    var sizeString: String { "\(size)x\(size)" }
    var scaleString: String { "\(scale)x" }
}

var entries: [Entry] = []
for variant in variants {
    let pixels = variant.size * variant.scale
    let entry = Entry(size: variant.size, scale: variant.scale)
    guard let data = pngData(from: masterImage, pixels: pixels) else {
        FileHandle.standardError.write(Data("Failed to render \(pixels)px\n".utf8))
        continue
    }
    try data.write(to: iconSetDir.appendingPathComponent(entry.filename))
    entries.append(entry)
    print("Wrote \(entry.filename) (\(pixels)px)")
}

// Contents.json for the icon set.
let imageObjs = entries.map { entry -> [String: String] in
    ["idiom": entry.idiom, "size": entry.sizeString,
     "scale": entry.scaleString, "filename": entry.filename]
}
let iconContents: [String: Any] = [
    "images": imageObjs,
    "info": ["version": 1, "author": "xcode"]
]
let iconJSON = try JSONSerialization.data(
    withJSONObject: iconContents, options: [.prettyPrinted, .sortedKeys])
try iconJSON.write(to: iconSetDir.appendingPathComponent("Contents.json"))

// Top-level asset catalog Contents.json.
let catalogContents: [String: Any] = ["info": ["version": 1, "author": "xcode"]]
let catalogJSON = try JSONSerialization.data(
    withJSONObject: catalogContents, options: [.prettyPrinted, .sortedKeys])
try catalogJSON.write(to: assetsDir.appendingPathComponent("Contents.json"))

print("Done. Icon set written to \(iconSetDir.path)")
