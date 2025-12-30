//
//  CompressionModels.swift
//  PDFHandler
//
//  Data models for PDF compression
//

import Foundation

// MARK: - Compression Options

struct CompressionOptions {
    var preset: GhostscriptPreset = .ebook
    var targetRatio: Double = 0.5
    var imageDPI: Int = 150
    var colorImageCompression: ColorImageCompression = .jpeg
    var convertToGrayscale: Bool = false
    var fontHandling: FontHandling = .subset
    var preserveMetadata: Bool = true
    var outputDirectory: URL?
    var customOutputName: String?
}

enum GhostscriptPreset: String, CaseIterable, Identifiable {
    case prepress = "/prepress"
    case printer = "/printer"
    case ebook = "/ebook"
    case screen = "/screen"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prepress: return "Prepress (Print-ready, Archival)"
        case .printer: return "Printer (High-quality Printing)"
        case .ebook: return "eBook (Digital Distribution)"
        case .screen: return "Screen (Web/Email Sharing)"
        }
    }

    var description: String {
        switch self {
        case .prepress: return "Maximum quality, suitable for professional printing"
        case .printer: return "High quality, good for office printing"
        case .ebook: return "Good quality, optimized for digital reading"
        case .screen: return "Lower quality, smallest file size"
        }
    }

    var typicalRatioRange: ClosedRange<Double> {
        switch self {
        case .prepress: return 0.90...1.0
        case .printer: return 0.60...0.90
        case .ebook: return 0.30...0.60
        case .screen: return 0.10...0.30
        }
    }

    var defaultDPI: Int {
        switch self {
        case .prepress: return 300
        case .printer: return 300
        case .ebook: return 150
        case .screen: return 72
        }
    }

    static func forRatio(_ ratio: Double) -> GhostscriptPreset {
        switch ratio {
        case 0.90...1.0: return .prepress
        case 0.60..<0.90: return .printer
        case 0.30..<0.60: return .ebook
        default: return .screen
        }
    }
}

enum ColorImageCompression: String, CaseIterable, Identifiable {
    case jpeg = "JPEG"
    case jpeg2000 = "JPEG2000"
    case flate = "Flate"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG (Best compatibility)"
        case .jpeg2000: return "JPEG2000 (Better quality)"
        case .flate: return "Flate/ZIP (Lossless)"
        }
    }

    var ghostscriptValue: String {
        switch self {
        case .jpeg: return "/DCTEncode"
        case .jpeg2000: return "/JPXEncode"
        case .flate: return "/FlateEncode"
        }
    }
}

enum FontHandling: String, CaseIterable, Identifiable {
    case subset = "subset"
    case embed = "embed"
    case unembed = "unembed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .subset: return "Subset (Include only used characters)"
        case .embed: return "Embed (Include full fonts)"
        case .unembed: return "Unembed (Remove fonts, smaller size)"
        }
    }
}

// MARK: - Compression Result

struct CompressionResult: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64
    let preset: GhostscriptPreset
    let processingTime: TimeInterval
    let warnings: [CompressionWarning]

    var compressionRatio: Double {
        guard originalSize > 0 else { return 1.0 }
        return Double(compressedSize) / Double(originalSize)
    }

    var savedBytes: Int64 {
        originalSize - compressedSize
    }

    var savedPercentage: Double {
        guard originalSize > 0 else { return 0 }
        return Double(savedBytes) / Double(originalSize) * 100
    }

    var formattedOriginalSize: String {
        ByteCountFormatter.string(fromByteCount: originalSize, countStyle: .file)
    }

    var formattedCompressedSize: String {
        ByteCountFormatter.string(fromByteCount: compressedSize, countStyle: .file)
    }

    var formattedSavedSize: String {
        ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file)
    }
}

struct CompressionWarning: Identifiable {
    let id = UUID()
    let type: WarningType
    let message: String

    enum WarningType {
        case qualityLoss
        case fontIssue
        case imageDownsampled
        case metadataStripped
        case ghostscriptError
    }
}

// MARK: - Compression Preview

struct CompressionPreview {
    let originalSize: Int64
    let estimatedSize: Int64
    let preset: GhostscriptPreset
    let qualityIndicator: QualityIndicator

    var estimatedRatio: Double {
        guard originalSize > 0 else { return 1.0 }
        return Double(estimatedSize) / Double(originalSize)
    }

    enum QualityIndicator: String {
        case excellent = "Excellent"
        case good = "Good"
        case acceptable = "Acceptable"
        case noticeable = "Noticeable Loss"

        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "blue"
            case .acceptable: return "orange"
            case .noticeable: return "red"
            }
        }
    }
}

// MARK: - Ghostscript Command Builder

struct GhostscriptCommand {
    let inputPath: String
    let outputPath: String
    let options: CompressionOptions

    var arguments: [String] {
        var args = [
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            "-dPDFSETTINGS=\(options.preset.rawValue)",
            "-dNOPAUSE",
            "-dQUIET",
            "-dBATCH"
        ]

        // DPI settings
        args.append("-dDownsampleColorImages=true")
        args.append("-dColorImageResolution=\(options.imageDPI)")
        args.append("-dDownsampleGrayImages=true")
        args.append("-dGrayImageResolution=\(options.imageDPI)")
        args.append("-dDownsampleMonoImages=true")
        args.append("-dMonoImageResolution=\(min(options.imageDPI * 2, 300))")

        // Image compression
        args.append("-dAutoFilterColorImages=false")
        args.append("-dColorImageFilter=\(options.colorImageCompression.ghostscriptValue)")

        // Grayscale conversion
        if options.convertToGrayscale {
            args.append("-sColorConversionStrategy=Gray")
            args.append("-dProcessColorModel=/DeviceGray")
        }

        // Font handling
        switch options.fontHandling {
        case .subset:
            args.append("-dSubsetFonts=true")
            args.append("-dEmbedAllFonts=true")
        case .embed:
            args.append("-dSubsetFonts=false")
            args.append("-dEmbedAllFonts=true")
        case .unembed:
            args.append("-dEmbedAllFonts=false")
        }

        // Metadata
        if !options.preserveMetadata {
            args.append("-dFastWebView=false")
        }

        // Output
        args.append("-sOutputFile=\(outputPath)")
        args.append(inputPath)

        return args
    }

    var commandString: String {
        "gs " + arguments.joined(separator: " ")
    }
}
