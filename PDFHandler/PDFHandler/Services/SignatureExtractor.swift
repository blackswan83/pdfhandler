//
//  SignatureExtractor.swift
//  PDFHandler
//
//  Isolates pen ink from a photo or scan of a signature on paper and
//  returns it on a transparent background, so it composites over
//  ruled lines and body text as if written there.
//
//  Why not a simple white-knockout threshold (what this replaces):
//  a fixed "brighter than 90% is background" cut assumes evenly-lit,
//  truly-white paper. A phone photo has none of that — it has a
//  lighting gradient, a shadow down one side, off-white or yellowish
//  paper, and JPEG noise. A global threshold either eats the faint
//  parts of the stroke or leaves a grey slab around it, and because
//  the cut is binary the edges come out jagged.
//
//  The approach here:
//    1. Estimate the paper brightness LOCALLY, per tile, so shadows
//       and gradients are handled rather than fought.
//    2. Produce a continuous alpha matte from how far each pixel sits
//       below its local paper level, which keeps stroke edges
//       anti-aliased and pressure variation intact.
//    3. Drop connected specks below a size floor — paper grain and
//       compression artefacts — using component labelling rather than
//       morphological erosion, which would eat thin strokes.
//    4. Crop to the ink so the saved asset has no dead margins.
//
//  The API is split into raster-in / raster-out around a pure core so
//  the expensive part can run off the main thread: NSImage is not
//  Sendable and cannot cross an actor boundary, but a Raster is.
//

import Foundation
import AppKit
import CoreGraphics

enum SignatureExtractor {

    struct Options: Sendable {
        /// 0…1. Higher captures fainter ink at the cost of admitting
        /// more paper texture.
        var sensitivity: Double = 0.5
        /// Working resolution cap. A signature is placed at a couple
        /// of hundred points; beyond this is cost without benefit.
        var maxDimension: Int = 1800
    }

    /// RGBA8 pixels that can cross actor boundaries — unlike NSImage.
    struct Raster: Sendable {
        var bytes: [UInt8]
        var width: Int
        var height: Int
    }

    // MARK: - Convenience

    /// Whole pipeline in one call, for callers not worried about
    /// blocking. The UI uses the three-step form so the middle step
    /// can run off the main thread.
    static func extract(from image: NSImage, options: Options = Options()) -> NSImage? {
        guard let input = raster(from: image, maxDimension: options.maxDimension),
              let output = extract(input, options: options)
        else { return nil }
        return self.image(from: output)
    }

    // MARK: - Step 1: NSImage → Raster (main thread)

    static func raster(from image: NSImage, maxDimension: Int) -> Raster? {
        guard let cg = downscaled(image, maxDimension: CGFloat(maxDimension)) else { return nil }
        let width = cg.width, height = cg.height
        guard width > 8, height > 8,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let ctx = CGContext(
                    data: base, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  )
            else { return false }
            // White backdrop so a transparent input reads as paper.
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? Raster(bytes: bytes, width: width, height: height) : nil
    }

    // MARK: - Step 2: the pure core (safe off the main thread)

    /// Returns premultiplied RGBA with black ink, cropped to the
    /// strokes, or nil when no ink is discernible.
    static func extract(_ input: Raster, options: Options) -> Raster? {
        let width = input.width, height = input.height
        let count = width * height
        guard count > 64 else { return nil }

        // 1. Luminance.
        var luma = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let r = Float(input.bytes[i * 4])
            let g = Float(input.bytes[i * 4 + 1])
            let b = Float(input.bytes[i * 4 + 2])
            luma[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }

        // 2. Local paper level, and a global ink level from the
        //    darkest few percent.
        let paper = paperLevelField(luma: luma, width: width, height: height)
        let inkLevel = percentile(luma, 0.03)

        // 3. Continuous alpha matte. Higher sensitivity lowers the
        //    floor, admitting fainter ink.
        let floor = Float(0.06 + (1.0 - min(max(options.sensitivity, 0), 1)) * 0.22)
        var alpha = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let bg = paper[i]
            // The span floor matters when ink is a small fraction of
            // the frame: the dark percentile then lands on paper, the
            // span collapses, and a small floor amplifies paper grain
            // into the matte. 40 keeps ±6 levels of JPEG noise under
            // the alpha floor while genuine ink still saturates.
            let span = max(bg - inkLevel, 40)
            let raw = (bg - luma[i]) / span         // 0 at paper, 1 at ink
            alpha[i] = min(max((raw - floor) / max(1 - floor, 0.01), 0), 1)
        }

        // 4. Remove specks: paper grain, dust, compression noise.
        removeSmallComponents(&alpha, width: width, height: height)

        // 5. Crop to the ink and composite.
        guard let box = inkBounds(alpha, width: width, height: height) else { return nil }
        return composite(alpha: alpha, width: width, crop: box)
    }

    // MARK: - Step 3: Raster → NSImage (main thread)

    static func image(from raster: Raster) -> NSImage? {
        guard raster.width > 0, raster.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(raster.bytes) as CFData),
              let cg = CGImage(
                width: raster.width, height: raster.height,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: raster.width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil,
                shouldInterpolate: true, intent: .defaultIntent
              )
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: raster.width, height: raster.height))
    }

    // MARK: - Opacity check

    /// Whether the image still sits on an opaque card. A properly
    /// isolated signature has see-through borders; a photo, scan or
    /// pre-extraction import does not. Drives the "isolate ink"
    /// affordance in the library list, so it only appears on entries
    /// that actually need it.
    static func hasOpaqueBackground(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        switch cg.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return true // no alpha channel at all
        default:
            break
        }

        let side = 24
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let ctx = CGContext(
                    data: base, width: side, height: side, bitsPerComponent: 8,
                    bytesPerRow: side * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return false }

        // Sample the border ring: an isolated signature (which is
        // cropped with a margin) is transparent along its edges; an
        // opaque card is solid all the way around.
        var opaque = 0, total = 0
        for y in 0..<side {
            for x in 0..<side where x == 0 || y == 0 || x == side - 1 || y == side - 1 {
                total += 1
                if bytes[(y * side + x) * 4 + 3] > 245 { opaque += 1 }
            }
        }
        return total > 0 && Double(opaque) / Double(total) > 0.9
    }

    // MARK: - Paper level

    /// Per-pixel estimate of the paper's brightness, from a coarse grid
    /// of local high percentiles interpolated bilinearly. Coarse on
    /// purpose: it must model the lighting, not the strokes.
    private static func paperLevelField(luma: [Float], width: Int, height: Int) -> [Float] {
        let tileW = max(1, width / 10), tileH = max(1, height / 10)
        let cols = max(1, Int(ceil(Double(width) / Double(tileW))))
        let rows = max(1, Int(ceil(Double(height) / Double(tileH))))

        var grid = [Float](repeating: 255, count: cols * rows)
        var scratch: [Float] = []
        scratch.reserveCapacity(tileW * tileH)

        for row in 0..<rows {
            for col in 0..<cols {
                scratch.removeAll(keepingCapacity: true)
                let x0 = col * tileW, x1 = min(width, x0 + tileW)
                let y0 = row * tileH, y1 = min(height, y0 + tileH)
                guard x0 < x1, y0 < y1 else { continue }
                for y in y0..<y1 {
                    let base = y * width
                    for x in x0..<x1 { scratch.append(luma[base + x]) }
                }
                // 80th percentile: above most ink, below specular glare.
                grid[row * cols + col] = percentile(scratch, 0.80)
            }
        }

        var field = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let gy = min(Double(rows - 1), max(0, Double(y) / Double(tileH) - 0.5))
            let y0 = Int(gy), y1 = min(rows - 1, y0 + 1)
            let fy = Float(gy - Double(y0))
            for x in 0..<width {
                let gx = min(Double(cols - 1), max(0, Double(x) / Double(tileW) - 0.5))
                let x0 = Int(gx), x1 = min(cols - 1, x0 + 1)
                let fx = Float(gx - Double(x0))
                let top = grid[y0 * cols + x0] * (1 - fx) + grid[y0 * cols + x1] * fx
                let bot = grid[y1 * cols + x0] * (1 - fx) + grid[y1 * cols + x1] * fx
                field[y * width + x] = top * (1 - fy) + bot * fy
            }
        }
        return field
    }

    private static func percentile(_ values: [Float], _ q: Double) -> Float {
        guard !values.isEmpty else { return 255 }
        let sorted = values.sorted()
        let idx = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * q)))
        return sorted[idx]
    }

    // MARK: - Despeckle

    /// Zeroes connected regions smaller than a size floor. Component
    /// labelling rather than an erode/dilate opening: a 3x3 erosion
    /// deletes any stroke thinner than three pixels, which is most of
    /// a fine-pen signature at this resolution.
    private static func removeSmallComponents(_ alpha: inout [Float], width: Int, height: Int) {
        let count = width * height
        let threshold: Float = 0.18
        let minimumSize = max(10, count / 8000)

        var visited = [Bool](repeating: false, count: count)
        var stack: [Int] = []
        var component: [Int] = []

        for start in 0..<count {
            // Inlined rather than a closure: capturing `alpha` in one
            // would escape an inout parameter, which Swift rejects.
            guard !visited[start], alpha[start] > threshold else { continue }

            stack.removeAll(keepingCapacity: true)
            component.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true

            while let idx = stack.popLast() {
                component.append(idx)
                let x = idx % width, y = idx / width
                // 8-connected: diagonal continuity matters for strokes.
                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0, ny < height else { continue }
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nx = x + dx
                        guard nx >= 0, nx < width else { continue }
                        let n = ny * width + nx
                        if !visited[n], alpha[n] > threshold {
                            visited[n] = true
                            stack.append(n)
                        }
                    }
                }
            }

            if component.count < minimumSize {
                for idx in component { alpha[idx] = 0 }
            }
        }
    }

    // MARK: - Bounds + composite

    private static func inkBounds(_ alpha: [Float], width: Int, height: Int) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let base = y * width
            for x in 0..<width where alpha[base + x] > 0.08 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let margin = max(2, Int(Double(max(maxX - minX, maxY - minY)) * 0.03))
        minX = max(0, minX - margin); minY = max(0, minY - margin)
        maxX = min(width - 1, maxX + margin); maxY = min(height - 1, maxY + margin)
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Black ink, premultiplied so anti-aliased edges blend without
    /// halos. Ink is re-coloured rather than sampled: pen on paper
    /// photographs as muddy grey-blue, which looks wrong beside the
    /// document's own black text.
    private static func composite(alpha: [Float], width: Int, crop: CGRect) -> Raster? {
        let cw = Int(crop.width), ch = Int(crop.height)
        guard cw > 0, ch > 0 else { return nil }

        var out = [UInt8](repeating: 0, count: cw * ch * 4)
        for y in 0..<ch {
            let srcRow = (Int(crop.minY) + y) * width + Int(crop.minX)
            let dstRow = y * cw * 4
            for x in 0..<cw {
                let a = min(max(alpha[srcRow + x], 0), 1)
                let o = dstRow + x * 4
                // RGB stays 0 (black) premultiplied; only alpha varies.
                out[o + 3] = UInt8(a * 255)
            }
        }
        return Raster(bytes: out, width: cw, height: ch)
    }

    // MARK: - Input plumbing

    private static func downscaled(_ image: NSImage, maxDimension: CGFloat) -> CGImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(source.width), h = CGFloat(source.height)
        let longest = max(w, h)
        guard longest > maxDimension else { return source }

        let scale = maxDimension / longest
        let tw = Int(w * scale), th = Int(h * scale)
        guard tw > 0, th > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return source }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage() ?? source
    }
}
