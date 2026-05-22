//
//  CompressionService.swift
//  PDFHandler
//
//  PDF compression via the system Ghostscript binary. Shells out to
//  `gs` with the classic four presets (prepress / printer / ebook /
//  screen) plus a target-size ratio, grayscale and metadata toggles.
//
//  Progress is reported from stderr/stdout readability handlers, which
//  Foundation delivers on a background queue. Those @Sendable closures
//  must NOT mutate captured `var`s directly, so we keep the counters
//  inside a lock-guarded reference class (GhostscriptProgressState) —
//  same proven pattern that was in commit 136a048.
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
        case .prepress: return "Print-ready / archival, 300 DPI"
        case .printer:  return "High-quality printing, 300 DPI"
        case .ebook:    return "Digital distribution, 150 DPI"
        case .screen:   return "Web / email, 72 DPI"
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

    /// The sensible target-ratio range each preset implies.
    var suggestedRatioRange: ClosedRange<Double> {
        switch self {
        case .prepress: return 0.9...1.0
        case .printer:  return 0.6...0.9
        case .ebook:    return 0.3...0.6
        case .screen:   return 0.1...0.3
        }
    }

    /// Pick the preset whose range covers (or is closest to) `ratio`.
    static func forRatio(_ ratio: Double) -> GhostscriptPreset {
        for preset in [GhostscriptPreset.prepress, .printer, .ebook, .screen] {
            if preset.suggestedRatioRange.contains(ratio) { return preset }
        }
        return .ebook
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

    func compress(
        pdfURL: URL,
        preset: GhostscriptPreset,
        targetRatio: Double,
        grayscale: Bool,
        preserveMetadata: Bool,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> CompressionResult {

        let startTime = Date()

        guard FileManager.default.isReadableFile(atPath: pdfURL.path) else {
            throw CompressionError.invalidInput
        }
        guard let gsPath = Self.findGhostscript() else {
            throw CompressionError.ghostscriptNotFound
        }

        let originalSize = (try? FileManager.default.attributesOfItem(atPath: pdfURL.path)[.size] as? Int64) ?? 0

        let outputURL = pdfURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(pdfURL.deletingPathExtension().lastPathComponent)_compressed.pdf")

        let arguments = Self.buildArguments(
            input: pdfURL.path,
            output: outputURL.path,
            preset: preset,
            grayscale: grayscale,
            preserveMetadata: preserveMetadata
        )

        try await runGhostscript(
            path: gsPath,
            arguments: arguments,
            progressHandler: progressHandler
        )

        let compressedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
        guard compressedSize > 0 else { throw CompressionError.cannotWrite }

        _ = targetRatio // surfaced in UI; the preset itself drives gs settings

        return CompressionResult(
            sourceURL: pdfURL,
            outputURL: outputURL,
            originalSize: originalSize,
            compressedSize: compressedSize,
            preset: preset,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Ghostscript invocation

    private func runGhostscript(
        path: String,
        arguments: [String],
        progressHandler: @escaping (Double) -> Void
    ) async throws {

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

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
                let updated = progress.bumpStderr()
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
                DispatchQueue.main.async {
                    if proc.terminationStatus == 0 {
                        progressHandler(1.0)
                        continuation.resume()
                    } else {
                        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let message = String(data: errData, encoding: .utf8) ?? "exit code \(proc.terminationStatus)"
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

    // MARK: - Helpers

    private static func buildArguments(
        input: String,
        output: String,
        preset: GhostscriptPreset,
        grayscale: Bool,
        preserveMetadata: Bool
    ) -> [String] {
        var args: [String] = [
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            "-dPDFSETTINGS=\(preset.gsSettings)",
            "-dNOPAUSE",
            "-dQUIET",
            "-dBATCH",
            "-sOutputFile=\(output)"
        ]
        if grayscale {
            args += [
                "-sProcessColorModel=DeviceGray",
                "-sColorConversionStrategy=Gray",
                "-dOverrideICC"
            ]
        }
        if !preserveMetadata {
            args += ["-dPrinted=false"]
        }
        args.append(input)
        return args
    }

    static func findGhostscript() -> String? {
        let candidates = [
            "/opt/homebrew/bin/gs",
            "/usr/local/bin/gs",
            "/usr/bin/gs",
            "/opt/local/bin/gs",
            "/sw/bin/gs"
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return resolveViaWhich()
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

    /// Any stderr activity bumps progress up to 0.95.
    func bumpStderr() -> Double {
        lock.lock(); defer { lock.unlock() }
        lastProgress = min(lastProgress + 0.05, 0.95)
        return lastProgress
    }

    /// Any stdout activity bumps progress up to 0.9; nil if already past.
    func bumpStdout() -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard lastProgress < 0.9 else { return nil }
        lastProgress = min(lastProgress + 0.02, 0.9)
        return lastProgress
    }
}
