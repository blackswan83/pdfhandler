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
        grayscale: Bool,
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
            grayscale: grayscale
        )

        try await runGhostscript(
            path: gsPath,
            arguments: arguments,
            progressHandler: progressHandler
        )

        let compressedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
        guard compressedSize > 0 else { throw CompressionError.cannotWrite }

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

    // MARK: - Helpers

    private static func buildArguments(
        input: String,
        output: String,
        preset: GhostscriptPreset,
        grayscale: Bool
    ) -> [String] {
        // No -dQUIET: the per-page "Processing pages" chatter is what
        // drives the progress ticks in the readability handlers.
        var args: [String] = [
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            "-dPDFSETTINGS=\(preset.gsSettings)",
            "-dNOPAUSE",
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
