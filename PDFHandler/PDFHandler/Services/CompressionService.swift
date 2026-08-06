//
//  CompressionService.swift
//  PDFHandler
//
//  PDF compression via the system Ghostscript binary.
//
//  Why Ghostscript: it remains the strongest open-source PDF
//  re-distiller (its only real peer, MuPDF, is from the same authors
//  and is aimed at in-process Python/C pipelines rather than a CLI).
//  The presets alone, however, leave a lot on the table — they name a
//  target resolution without switching downsampling on, and they pin
//  the output to PDF 1.4, which forbids the compressed object and
//  cross-reference streams that shrink the file structure itself.
//  Every parameter below is therefore applied AFTER -dPDFSETTINGS,
//  because Ghostscript processes options left to right and the preset
//  assigns a whole bundle of Distiller parameters when it is read.
//
//  Progress is reported from stderr/stdout readability handlers, which
//  Foundation delivers on a background queue. Those @Sendable closures
//  must NOT mutate captured `var`s directly, so we keep the counters
//  inside a lock-guarded reference class (GhostscriptProgressState).
//

import Foundation
import AppKit

// MARK: - Presets

enum GhostscriptPreset: String, CaseIterable, Identifiable, Codable {
    case prepress, printer, ebook, screen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prepress: return "Prepress"
        case .printer:  return "Printer"
        case .ebook:    return "eBook"
        case .screen:   return "Screen"
        }
    }

    var summary: String {
        switch self {
        case .prepress: return "Print-ready / archival, 300 DPI images"
        case .printer:  return "High-quality printing, 300 DPI images"
        case .ebook:    return "Digital distribution, 150 DPI images"
        case .screen:   return "Web / email, 72 DPI images"
        }
    }

    /// Ghostscript's `-dPDFSETTINGS=...` argument value.
    var gsSettings: String {
        switch self {
        case .prepress: return "/prepress"
        case .printer:  return "/printer"
        case .ebook:    return "/ebook"
        case .screen:   return "/screen"
        }
    }

    /// Colour / grayscale image resolution the preset targets. Stated
    /// explicitly so downsampling can actually be enforced.
    var imageResolution: Int {
        switch self {
        case .prepress, .printer: return 300
        case .ebook:              return 150
        case .screen:             return 72
        }
    }
}

/// What the Compress pane is set to do. Target-size sits alongside the
/// quality presets rather than modifying them: it searches for a
/// resolution rather than accepting the preset's, so presenting it as
/// a modifier of one implied a relationship that does not exist.
enum CompressMode: String, CaseIterable, Identifiable, Codable {
    case prepress, printer, ebook, screen, targetSize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prepress:   return "Prepress"
        case .printer:    return "Printer"
        case .ebook:      return "eBook"
        case .screen:     return "Screen"
        case .targetSize: return "Target size"
        }
    }

    var preset: GhostscriptPreset {
        switch self {
        case .prepress:   return .prepress
        case .printer:    return .printer
        case .ebook:      return .ebook
        case .screen:     return .screen
        // Start the search from the top so quality is bought back as
        // far as the target allows.
        case .targetSize: return .printer
        }
    }

    var isTargetSize: Bool { self == .targetSize }

    var summary: String {
        isTargetSize
            ? "Searches image resolution for the best quality that fits your target."
            : preset.summary
    }

    /// Typical output as a fraction of the original for image-heavy
    /// PDFs. A range, and labelled as typical, because the true figure
    /// depends entirely on what is inside the file — a text-only PDF
    /// barely moves.
    var typicalRange: ClosedRange<Double>? {
        switch self {
        case .prepress:   return 0.75...1.0
        case .printer:    return 0.5...0.85
        case .ebook:      return 0.25...0.6
        case .screen:     return 0.1...0.35
        case .targetSize: return nil
        }
    }
}

// MARK: - Result + errors

struct CompressionResult {
    let sourceURL: URL
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64
    let preset: GhostscriptPreset
    let processingTime: TimeInterval
    /// Image resolution the winning pass used, when target-size mode
    /// searched for one.
    let resolvedDPI: Int?
    /// True when target-size mode could not reach the requested size
    /// even at its most aggressive setting.
    let missedTarget: Bool

    var savingsPercent: Double {
        guard originalSize > 0 else { return 0 }
        return 1.0 - (Double(compressedSize) / Double(originalSize))
    }
}

enum CompressionError: LocalizedError {
    case ghostscriptNotFound
    case ghostscriptFailed(String)
    case invalidInput
    case cannotWrite

    var errorDescription: String? {
        switch self {
        case .ghostscriptNotFound:
            return "Ghostscript (gs) is not installed. Run: brew install ghostscript"
        case .ghostscriptFailed(let message):
            return "Ghostscript failed: \(message)"
        case .invalidInput:
            return "The selected file is not a readable PDF."
        case .cannotWrite:
            return "Could not write the compressed PDF."
        }
    }
}

// MARK: - Service

actor CompressionService {

    /// Most aggressive image resolution the target-size search will try.
    private static let minSearchDPI = 36
    /// Passes the target-size search is allowed. Binary search over the
    /// DPI range converges well inside this.
    private static let maxSearchPasses = 5

    /// Compresses `pdfURL` next to itself as `<name>_compressed.pdf`.
    ///
    /// With `targetFraction` nil this is a single Ghostscript pass at
    /// the preset's own resolution. With a target set, it binary
    /// searches image resolution for the *highest* quality that still
    /// lands under the requested fraction of the original size —
    /// which is what actually answers "make this as small as it needs
    /// to be" rather than guessing at a preset.
    func compress(
        pdfURL: URL,
        preset: GhostscriptPreset,
        grayscale: Bool,
        targetFraction: Double?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> CompressionResult {

        let startTime = Date()

        guard FileManager.default.isReadableFile(atPath: pdfURL.path) else {
            throw CompressionError.invalidInput
        }
        guard let gs = Self.locateGhostscript() else {
            throw CompressionError.ghostscriptNotFound
        }

        let originalSize = Self.fileSize(pdfURL)
        let outputURL = pdfURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(pdfURL.deletingPathExtension().lastPathComponent)_compressed.pdf")

        let finalSize: Int64
        let resolvedDPI: Int?
        var missedTarget = false

        if let targetFraction {
            let outcome = try await searchForTarget(
                gs: gs,
                pdfURL: pdfURL,
                outputURL: outputURL,
                preset: preset,
                grayscale: grayscale,
                originalSize: originalSize,
                targetFraction: targetFraction,
                progressHandler: progressHandler
            )
            finalSize = outcome.size
            resolvedDPI = outcome.dpi
            missedTarget = outcome.missedTarget
        } else {
            try await runGhostscript(
                gs: gs,
                arguments: Self.buildArguments(
                    input: pdfURL.path,
                    output: outputURL.path,
                    preset: preset,
                    grayscale: grayscale,
                    imageDPI: nil
                ),
                progressHandler: progressHandler
            )
            finalSize = Self.fileSize(outputURL)
            resolvedDPI = nil
        }

        guard finalSize > 0 else { throw CompressionError.cannotWrite }

        return CompressionResult(
            sourceURL: pdfURL,
            outputURL: outputURL,
            originalSize: originalSize,
            compressedSize: finalSize,
            preset: preset,
            processingTime: Date().timeIntervalSince(startTime),
            resolvedDPI: resolvedDPI,
            missedTarget: missedTarget
        )
    }

    // MARK: - Target-size search

    private struct SearchOutcome {
        let size: Int64
        let dpi: Int
        let missedTarget: Bool
    }

    private func searchForTarget(
        gs: GhostscriptLocation,
        pdfURL: URL,
        outputURL: URL,
        preset: GhostscriptPreset,
        grayscale: Bool,
        originalSize: Int64,
        targetFraction: Double,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> SearchOutcome {

        let targetBytes = Int64(Double(originalSize) * targetFraction)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfhandler-compress-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var low = Self.minSearchDPI
        var high = max(preset.imageResolution, Self.minSearchDPI)

        // Best = highest DPI that met the target. Fallback = smallest
        // file seen, used when even the floor overshoots.
        var best: (url: URL, size: Int64, dpi: Int)?
        var smallest: (url: URL, size: Int64, dpi: Int)?

        for pass in 0..<Self.maxSearchPasses where low <= high {
            let dpi = (low + high) / 2
            let candidate = scratch.appendingPathComponent("pass-\(pass).pdf")

            try await runGhostscript(
                gs: gs,
                arguments: Self.buildArguments(
                    input: pdfURL.path,
                    output: candidate.path,
                    preset: preset,
                    grayscale: grayscale,
                    imageDPI: dpi
                ),
                // Each pass owns a slice of the overall progress bar.
                progressHandler: { inner in
                    let span = 1.0 / Double(Self.maxSearchPasses)
                    progressHandler(min(0.99, (Double(pass) + inner) * span))
                }
            )

            let size = Self.fileSize(candidate)
            guard size > 0 else { break }

            if smallest == nil || size < smallest!.size {
                smallest = (candidate, size, dpi)
            }
            if size <= targetBytes {
                // Met the target — try to buy back quality.
                best = (candidate, size, dpi)
                low = dpi + 1
            } else {
                high = dpi - 1
            }
        }

        guard let winner = best ?? smallest else {
            throw CompressionError.cannotWrite
        }

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(at: winner.url, to: outputURL)
        progressHandler(1.0)

        return SearchOutcome(
            size: winner.size,
            dpi: winner.dpi,
            missedTarget: best == nil
        )
    }

    // MARK: - Ghostscript invocation

    private func runGhostscript(
        gs: GhostscriptLocation,
        arguments: [String],
        progressHandler: @escaping (Double) -> Void
    ) async throws {

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: gs.executablePath)
            process.arguments = arguments
            if let libraryPath = gs.libraryPath {
                // A bundled gs cannot initialize without its Resource
                // tree (gs_init.ps, fonts, ICC profiles).
                var env = ProcessInfo.processInfo.environment
                env["GS_LIB"] = libraryPath
                process.environment = env
            }

            let stderrPipe = Pipe()
            let stdoutPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = stdoutPipe

            // Shared progress counters — closures capture a reference,
            // never a mutable local var, so @Sendable checking passes.
            let progress = GhostscriptProgressState()

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                // Keep the bytes: they're the only error detail gs
                // produces, and draining them here would otherwise
                // leave the failure banner empty.
                let updated = progress.bumpStderr(appending: data)
                DispatchQueue.main.async { progressHandler(updated) }
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let updated = progress.bumpStdout() {
                    DispatchQueue.main.async { progressHandler(updated) }
                }
            }

            process.terminationHandler = { proc in
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                let remaining = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? nil
                DispatchQueue.main.async {
                    if proc.terminationStatus == 0 {
                        progressHandler(1.0)
                        continuation.resume()
                    } else {
                        var errData = progress.collectedStderr()
                        if let remaining { errData.append(remaining) }
                        let text = String(data: errData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let message = text.isEmpty
                            ? "exit code \(proc.terminationStatus)"
                            : String(text.suffix(600))
                        continuation.resume(throwing: CompressionError.ghostscriptFailed(message))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: CompressionError.ghostscriptFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Arguments

    /// ORDER IS LOAD-BEARING. Ghostscript applies options left to
    /// right, and -dPDFSETTINGS assigns a whole bundle of Distiller
    /// parameters when it is read — so every override has to come
    /// after it or the preset silently wins.
    static func buildArguments(
        input: String,
        output: String,
        preset: GhostscriptPreset,
        grayscale: Bool,
        imageDPI: Int?
    ) -> [String] {
        var args: [String] = [
            "-sDEVICE=pdfwrite",
            "-dNOPAUSE",
            "-dBATCH",
            "-dSAFER",
            "-dPDFSETTINGS=\(preset.gsSettings)",
        ]

        // PDF 1.7 rather than the presets' 1.4: 1.5+ is what permits
        // compressed object and cross-reference streams, which shrink
        // the file's own structure. 1.7 (ISO 32000-1, 2008) is
        // universally readable.
        args.append("-dCompatibilityLevel=1.7")

        // The presets name a target resolution but leave downsampling
        // off, so images frequently pass through at full size. Turn it
        // on and pick the better resampling filter.
        let dpi = imageDPI ?? preset.imageResolution
        args += [
            "-dDownsampleColorImages=true",
            "-dDownsampleGrayImages=true",
            "-dDownsampleMonoImages=true",
            "-dColorImageDownsampleType=/Bicubic",
            "-dGrayImageDownsampleType=/Bicubic",
            // Bilevel art turns to mush under interpolation.
            "-dMonoImageDownsampleType=/Subsample",
            "-dColorImageResolution=\(dpi)",
            "-dGrayImageResolution=\(dpi)",
            // Scanned text lives in the mono channel — keep it legible
            // even when the colour images are crushed.
            "-dMonoImageResolution=\(max(dpi * 2, 300))",
            // Leave an image alone unless there is a real gain, rather
            // than resampling something already close to target.
            "-dColorImageDownsampleThreshold=1.2",
            "-dGrayImageDownsampleThreshold=1.2",
            "-dMonoImageDownsampleThreshold=1.2",
        ]

        args += [
            // One stored copy of a logo repeated on all 40 pages.
            "-dDetectDuplicateImages=true",
            "-dCompressFonts=true",
            "-dSubsetFonts=true",
            // Keep the document renderable on machines without the
            // fonts installed — a contract that reflows is worse than
            // a contract that is 40KB bigger.
            "-dEmbedAllFonts=true",
            // Presets otherwise re-orient pages from their content,
            // which silently rotates scanned documents.
            "-dAutoRotatePages=/None",
            // Linearize for fast first-page display.
            "-dFastWebView=true",
        ]

        if grayscale {
            args += [
                "-sProcessColorModel=DeviceGray",
                "-sColorConversionStrategy=Gray",
                "-dOverrideICC",
            ]
        }

        args += ["-sOutputFile=\(output)", input]
        return args
    }

    // MARK: - Helpers

    static func fileSize(_ url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    /// True when the PDF carries a cryptographic signature.
    ///
    /// Any re-distillation rewrites the file's bytes and therefore
    /// invalidates the /ByteRange digest a signature is computed over —
    /// Ghostscript cannot preserve one, and neither can any other
    /// re-writer. For a signing app that is worth warning about before
    /// destroying, not after.
    static func carriesDigitalSignature(url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        // /ByteRange only appears in a signature dictionary that has
        // actually been signed; an empty signature *field* has none.
        return data.range(of: Data("/ByteRange".utf8)) != nil
    }

    /// Where the Ghostscript executable lives, plus the GS_LIB search
    /// path when we are running a bundled copy (gs cannot initialize
    /// without finding Resource/Init/gs_init.ps).
    struct GhostscriptLocation {
        let executablePath: String
        let libraryPath: String?
    }

    /// Locates Ghostscript, preferring a copy bundled inside the app.
    ///
    /// A bundled binary is version-matched to what the app was tested
    /// against and removes the Homebrew prerequisite entirely. Note
    /// that Ghostscript is AGPL: bundling it is fine for a private
    /// build, but redistributing the result carries AGPL obligations
    /// (see README). Nothing is bundled by default — this simply makes
    /// a dropped-in copy work.
    static func locateGhostscript() -> GhostscriptLocation? {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "gs")?.path,
           FileManager.default.isExecutableFile(atPath: bundled),
           let libraryPath = bundledLibraryPath() {
            return GhostscriptLocation(executablePath: bundled, libraryPath: libraryPath)
        }

        let candidates = [
            "/opt/homebrew/bin/gs",
            "/usr/local/bin/gs",
            "/usr/bin/gs",
            "/opt/local/bin/gs",
            "/sw/bin/gs"
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return GhostscriptLocation(executablePath: candidate, libraryPath: nil)
        }
        return resolveViaWhich().map {
            GhostscriptLocation(executablePath: $0, libraryPath: nil)
        }
    }

    /// GS_LIB for a bundled Ghostscript, laid out by build-dmg.sh at
    /// Contents/Resources/ghostscript/{Resource,lib}. Returns nil when
    /// nothing is bundled, so the bundled executable is only used when
    /// its support files are actually present.
    private static func bundledLibraryPath() -> String? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let root = resources.appendingPathComponent("ghostscript")
        var isDir: ObjCBool = false
        let initDir = root.appendingPathComponent("Resource/Init")
        guard FileManager.default.fileExists(atPath: initDir.path, isDirectory: &isDir), isDir.boolValue
        else { return nil }
        return [
            initDir.path,
            root.appendingPathComponent("lib").path,
            root.appendingPathComponent("Resource").path,
        ].joined(separator: ":")
    }

    static func findGhostscript() -> String? {
        locateGhostscript()?.executablePath
    }

    private static func resolveViaWhich() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["gs"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let p = path, !p.isEmpty, FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
            return nil
        } catch {
            return nil
        }
    }
}

// MARK: - Lock-guarded progress state

/// Shared between the stderr / stdout readability handlers that
/// Process delivers on a background queue. Exposed as @unchecked
/// Sendable because all access is serialized through the internal
/// NSLock.
private final class GhostscriptProgressState: @unchecked Sendable {
    private let lock = NSLock()
    private var lastProgress: Double = 0.0
    private var stderrData = Data()

    /// Any stderr activity bumps progress up to 0.95; the bytes are
    /// retained so a failure can show gs's actual error text.
    func bumpStderr(appending chunk: Data) -> Double {
        lock.lock(); defer { lock.unlock() }
        if stderrData.count < 64 * 1024 { stderrData.append(chunk) }
        lastProgress = min(lastProgress + 0.05, 0.95)
        return lastProgress
    }

    func collectedStderr() -> Data {
        lock.lock(); defer { lock.unlock() }
        return stderrData
    }

    /// Any stdout activity bumps progress up to 0.9; nil if already past.
    func bumpStdout() -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard lastProgress < 0.9 else { return nil }
        lastProgress = min(lastProgress + 0.02, 0.9)
        return lastProgress
    }
}
