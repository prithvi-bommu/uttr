#!/usr/bin/env swift
// Renders a 1024x1024 placeholder app icon for Uttr:
// macOS-style rounded rect with an indigo->purple gradient and a white mic symbol.
// Usage: swift Scripts/render-placeholder-icon.swift <output.png>

import AppKit

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Design/AppIcon/uttr-icon-source.png"

let canvas: CGFloat = 1024
// Apple HIG: macOS icon artwork occupies ~824x824 centered on the 1024 canvas.
let artSize: CGFloat = 824
let artOrigin = (canvas - artSize) / 2
let cornerRadius: CGFloat = 185 // approximates the macOS squircle

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// Transparent canvas margin (required so macOS renders the standard shadow/inset)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()

// Rounded-rect background with vertical gradient
let rect = NSRect(x: artOrigin, y: artOrigin, width: artSize, height: artSize)
let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.95, alpha: 1.0), // indigo
    ending: NSColor(calibratedRed: 0.24, green: 0.12, blue: 0.55, alpha: 1.0)    // deep purple
)!
gradient.draw(in: path, angle: -90)

// White mic SF Symbol centered
let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .medium)
if let symbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    let symbolRect = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: symbolRect)
    symbolRect.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let drawSize = NSSize(width: tinted.size.width, height: tinted.size.height)
    let scale = min(420 / drawSize.height, 420 / drawSize.width)
    let w = drawSize.width * scale
    let h = drawSize.height * scale
    tinted.draw(in: NSRect(x: (canvas - w) / 2, y: (canvas - h) / 2, width: w, height: h))
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileManager.default.changeCurrentDirectoryPath("/")
    fputs("error: failed to encode PNG\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
do {
    try png.write(to: url)
    print("wrote \(outputPath) (\(Int(canvas))x\(Int(canvas)))")
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
