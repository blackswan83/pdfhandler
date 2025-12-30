//
//  ConversionModels.swift
//  PDFHandler
//
//  Data models for PDF conversion
//

import Foundation
import PDFKit

// MARK: - Conversion Options

struct ConversionOptions {
    var includeYAMLFrontmatter: Bool = true
    var imageOutputFormat: ImageFormat = .png
    var imageNamingConvention: ImageNamingConvention = .sequential
    var tableFallbackMode: TableFallbackMode = .codeBlock
    var outputDirectory: URL?
    var preserveLinks: Bool = true
    var extractImages: Bool = true
    var performOCR: Bool = true
    var ocrLanguages: [String] = ["en-US"]
}

enum ImageFormat: String, CaseIterable, Identifiable {
    case png = "png"
    case jpeg = "jpeg"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: return "PNG (Lossless)"
        case .jpeg: return "JPEG (Smaller)"
        }
    }

    var fileExtension: String { rawValue }
}

enum ImageNamingConvention: String, CaseIterable, Identifiable {
    case sequential = "sequential"
    case pageNumber = "page_number"
    case descriptive = "descriptive"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sequential: return "Sequential (image_001, image_002)"
        case .pageNumber: return "Page-based (page1_img1)"
        case .descriptive: return "Descriptive (figure_1, chart_2)"
        }
    }
}

enum TableFallbackMode: String, CaseIterable, Identifiable {
    case codeBlock = "code_block"
    case csv = "csv"
    case html = "html"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codeBlock: return "Code Block"
        case .csv: return "Export as CSV"
        case .html: return "HTML Table"
        }
    }
}

// MARK: - Conversion Result

struct ConversionResult: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let outputURL: URL
    let markdown: String
    let extractedImages: [ExtractedImage]
    let metadata: DocumentMetadata
    let ocrApplied: Bool
    let ocrConfidence: Double?
    let warnings: [ConversionWarning]
    let processingTime: TimeInterval
}

struct ExtractedImage: Identifiable {
    let id = UUID()
    let originalPage: Int
    let outputURL: URL
    let format: ImageFormat
    let dimensions: CGSize
    let markdownReference: String
}

struct DocumentMetadata {
    var title: String?
    var author: String?
    var subject: String?
    var keywords: [String]
    var creationDate: Date?
    var modificationDate: Date?
    var pageCount: Int
    var hasText: Bool
    var isScanned: Bool
}

struct ConversionWarning: Identifiable {
    let id = UUID()
    let type: WarningType
    let message: String
    let page: Int?

    enum WarningType {
        case complexTable
        case lowOCRConfidence
        case unsupportedElement
        case imageTooLarge
        case missingFont
    }
}

// MARK: - Parsed Content

struct ParsedPDFContent {
    var pages: [ParsedPage]
    var metadata: DocumentMetadata
    var requiresOCR: Bool
}

struct ParsedPage {
    let pageNumber: Int
    var elements: [PageElement]
    var images: [PDFImage]
    var rawText: String
    var ocrText: String?
    var ocrConfidence: Double?
}

enum PageElement {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletList(items: [String])
    case numberedList(items: [String])
    case table(Table)
    case codeBlock(text: String)
    case blockquote(text: String)
    case horizontalRule
    case image(reference: String)
    case link(text: String, url: String)
}

struct Table {
    var headers: [String]
    var rows: [[String]]
    var isComplex: Bool

    var columnCount: Int {
        max(headers.count, rows.first?.count ?? 0)
    }

    func toMarkdown() -> String {
        guard !headers.isEmpty || !rows.isEmpty else { return "" }

        var lines: [String] = []

        // Headers
        let headerRow = headers.isEmpty
            ? Array(repeating: "", count: columnCount)
            : headers
        lines.append("| " + headerRow.joined(separator: " | ") + " |")

        // Separator
        lines.append("| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |")

        // Rows
        for row in rows {
            let paddedRow = row + Array(repeating: "", count: max(0, columnCount - row.count))
            lines.append("| " + paddedRow.joined(separator: " | ") + " |")
        }

        return lines.joined(separator: "\n")
    }

    func toCodeBlock() -> String {
        var lines: [String] = []

        if !headers.isEmpty {
            lines.append(headers.joined(separator: "\t"))
            lines.append(String(repeating: "-", count: headers.joined(separator: "\t").count))
        }

        for row in rows {
            lines.append(row.joined(separator: "\t"))
        }

        return "```\n" + lines.joined(separator: "\n") + "\n```"
    }

    func toCSV() -> String {
        var lines: [String] = []

        if !headers.isEmpty {
            lines.append(headers.map { escapeCSV($0) }.joined(separator: ","))
        }

        for row in rows {
            lines.append(row.map { escapeCSV($0) }.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

struct PDFImage {
    let pageNumber: Int
    let imageIndex: Int
    let bounds: CGRect
    let imageData: Data?
}

// MARK: - YAML Frontmatter

struct YAMLFrontmatter {
    var title: String?
    var author: String?
    var date: Date?
    var source: String?
    var tags: [String]
    var custom: [String: String]

    func toString() -> String {
        var lines = ["---"]

        if let title = title {
            lines.append("title: \"\(escapeYAML(title))\"")
        }
        if let author = author {
            lines.append("author: \"\(escapeYAML(author))\"")
        }
        if let date = date {
            let formatter = ISO8601DateFormatter()
            lines.append("date: \(formatter.string(from: date))")
        }
        if let source = source {
            lines.append("source: \"\(escapeYAML(source))\"")
        }
        if !tags.isEmpty {
            lines.append("tags:")
            for tag in tags {
                lines.append("  - \(escapeYAML(tag))")
            }
        }
        for (key, value) in custom {
            lines.append("\(key): \"\(escapeYAML(value))\"")
        }

        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private func escapeYAML(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
