#!/usr/bin/env swift
//
//  render-icon.swift
//  PDFHandler
//
//  Deterministically renders the app icon at 1024x1024 as PNG and
//  then emits all 10 Contents.json-referenced sizes via `sips`. Run
//  from scripts/build-dmg.sh before actool.
//
//  Concept: rounded-square base (blue→navy gradient), a centered
//  white page with a folded top-right corner, and a dark-navy
//  signature stroke (a smooth S-swash) across the page.
//

import Foundation
import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - CLI entry

let fm = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let repoRoot = scriptURL
    .deletingLastPathComponent()    // scripts/
    .deletingLastPathComponent()    // repo root

let iconsetDir = repoRoot
    .appendingPathComponent("PDFHandler/PDFHandler/Resources/Assets.xcassets/AppIcon.appiconset")

guard fm.fileExists(atPath: iconsetDir.path) else {
    FileHandle.standardError.write(Data("error: AppIcon.appiconset not found at \(iconsetDir.path)\n".utf8))
    exit(1)
}

// MARK: - Master render (1024x1024)

func renderMaster() -> CGImage {
    let side: CGFloat = 1024
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: Int(side), height: Int(side),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create bitmap context")
    }

    // Fully transparent background
    ctx.clear(CGRect(x: 0, y: 0, width: side, height: side))

    // Rounded-square base with a blue→navy gradient
    let baseRect = CGRect(x: 0, y: 0, width: side, height: side)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: 224, cornerHeight: 224, transform: nil)
    ctx.saveGState()
    ctx.addPath(basePath)
    ctx.clip()
    if let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.23, green: 0.34, blue: 0.83, alpha: 1), // top-left #3A56D4
            CGColor(red: 0.12, green: 0.16, blue: 0.29, alpha: 1)  // bottom-right #1E2A4A
        ] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: side),
            end:   CGPoint(x: side, y: 0),
            options: []
        )
    }
    ctx.restoreGState()

    // Inner glow highlight at top-left for depth
    ctx.saveGState()
    ctx.addPath(basePath)
    ctx.clip()
    if let highlight = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
        ] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawRadialGradient(
            highlight,
            startCenter: CGPoint(x: side * 0.25, y: side * 0.80),
            startRadius: 0,
            endCenter: CGPoint(x: side * 0.25, y: side * 0.80),
            endRadius: side * 0.6,
            options: []
        )
    }
    ctx.restoreGState()

    // White page centered in the base, with folded top-right corner.
    let pageWidth: CGFloat = 576
    let pageHeight: CGFloat = 720
    let pageX = (side - pageWidth) / 2
    let pageY = (side - pageHeight) / 2 - 20   // nudge down slightly
    let foldSize: CGFloat = 96

    // Page body (rounded with fold removed from top-right).
    let pagePath = CGMutablePath()
    pagePath.move(to: CGPoint(x: pageX + 36, y: pageY))
    // bottom edge (remember: our y increases upward)
    pagePath.addLine(to: CGPoint(x: pageX + pageWidth - 36, y: pageY))
    pagePath.addArc(
        tangent1End: CGPoint(x: pageX + pageWidth, y: pageY),
        tangent2End: CGPoint(x: pageX + pageWidth, y: pageY + 36),
        radius: 36
    )
    pagePath.addLine(to: CGPoint(x: pageX + pageWidth, y: pageY + pageHeight - foldSize))
    // fold
    pagePath.addLine(to: CGPoint(x: pageX + pageWidth - foldSize, y: pageY + pageHeight))
    // top-left corner
    pagePath.addLine(to: CGPoint(x: pageX + 36, y: pageY + pageHeight))
    pagePath.addArc(
        tangent1End: CGPoint(x: pageX, y: pageY + pageHeight),
        tangent2End: CGPoint(x: pageX, y: pageY + pageHeight - 36),
        radius: 36
    )
    pagePath.addLine(to: CGPoint(x: pageX, y: pageY + 36))
    pagePath.addArc(
        tangent1End: CGPoint(x: pageX, y: pageY),
        tangent2End: CGPoint(x: pageX + 36, y: pageY),
        radius: 36
    )
    pagePath.closeSubpath()

    // Page shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -12),
        blur: 30,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
    )
    ctx.addPath(pagePath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Fold triangle (slightly darker)
    let foldPath = CGMutablePath()
    foldPath.move(to: CGPoint(x: pageX + pageWidth - foldSize, y: pageY + pageHeight))
    foldPath.addLine(to: CGPoint(x: pageX + pageWidth, y: pageY + pageHeight - foldSize))
    foldPath.addLine(to: CGPoint(x: pageX + pageWidth - foldSize, y: pageY + pageHeight - foldSize))
    foldPath.closeSubpath()
    ctx.addPath(foldPath)
    ctx.setFillColor(CGColor(red: 0.86, green: 0.88, blue: 0.93, alpha: 1))
    ctx.fillPath()

    // Signature stroke (dark navy cubic bezier) across the page.
    let ink = CGColor(red: 0.12, green: 0.16, blue: 0.29, alpha: 1.0)
    let strokePath = CGMutablePath()
    strokePath.move(to: CGPoint(x: pageX + 60, y: pageY + 300))
    strokePath.addCurve(
        to:       CGPoint(x: pageX + pageWidth - 60, y: pageY + 360),
        control1: CGPoint(x: pageX + 200, y: pageY + 180),
        control2: CGPoint(x: pageX + 360, y: pageY + 460)
    )

    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(24)
    ctx.setStrokeColor(ink)
    ctx.addPath(strokePath)
    ctx.strokePath()
    ctx.restoreGState()

    // A small trailing flourish dot
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(
        x: pageX + pageWidth - 90, y: pageY + 355,
        width: 18, height: 18
    ))

    guard let image = ctx.makeImage() else {
        fatalError("Could not create CGImage")
    }
    return image
}

// MARK: - Write helpers

func writePNG(_ image: CGImage, to url: URL) {
    try? fm.removeItem(at: url)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        FileHandle.standardError.write(Data("error: could not create destination for \(url.path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        FileHandle.standardError.write(Data("error: could not finalize image \(url.path)\n".utf8))
        exit(1)
    }
}

func resize(using sips: String, source: URL, side: Int, out: URL) {
    try? fm.removeItem(at: out)
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: sips)
    proc.arguments = ["-z", "\(side)", "\(side)", source.path, "--out", out.path]
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError  = FileHandle.nullDevice
    do {
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            FileHandle.standardError.write(Data("error: sips failed for \(out.lastPathComponent)\n".utf8))
            exit(1)
        }
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
}

// MARK: - Main

print("==> Rendering app icon master (1024x1024)")
let master = renderMaster()
let masterURL = iconsetDir.appendingPathComponent("icon_512x512@2x.png")
writePNG(master, to: masterURL)

let sips = "/usr/bin/sips"
guard fm.isExecutableFile(atPath: sips) else {
    FileHandle.standardError.write(Data("error: /usr/bin/sips not found; are you on macOS?\n".utf8))
    exit(1)
}

// All filenames referenced by Contents.json.
let variants: [(String, Int)] = [
    ("icon_16x16.png",        16),
    ("icon_16x16@2x.png",     32),
    ("icon_32x32.png",        32),
    ("icon_32x32@2x.png",     64),
    ("icon_128x128.png",     128),
    ("icon_128x128@2x.png",  256),
    ("icon_256x256.png",     256),
    ("icon_256x256@2x.png",  512),
    ("icon_512x512.png",     512)
    // icon_512x512@2x.png already written as the master.
]
for (name, side) in variants {
    let out = iconsetDir.appendingPathComponent(name)
    print("==> Resizing to \(name) (\(side)x\(side))")
    resize(using: sips, source: masterURL, side: side, out: out)
}

print("==> Icon set written to \(iconsetDir.path)")
