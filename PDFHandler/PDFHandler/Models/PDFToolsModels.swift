//
//  PDFToolsModels.swift
//  PDFHandler
//
//  Data models for PDF tools (merge, split, rotate, sign, etc.)
//

import Foundation
import AppKit

// MARK: - Split Options

enum SplitMode: String, CaseIterable, Identifiable {
    case allPages = "all_pages"
    case pageRanges = "page_ranges"
    case everyNPages = "every_n_pages"
    case byFileSize = "by_file_size"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allPages: return "Extract all pages"
        case .pageRanges: return "Specific page ranges"
        case .everyNPages: return "Every N pages"
        case .byFileSize: return "By file size"
        }
    }

    var description: String {
        switch self {
        case .allPages: return "Create a separate PDF for each page"
        case .pageRanges: return "e.g., 1-3, 5, 7-10"
        case .everyNPages: return "Split into chunks of N pages"
        case .byFileSize: return "Split when exceeding size limit"
        }
    }
}

struct SplitOptions {
    var mode: SplitMode = .allPages
    var pageRanges: String = ""
    var pagesPerSplit: Int = 1
    var maxFileSizeMB: Double = 10.0
    var outputDirectory: URL?
    var outputNamePrefix: String?
}

struct SplitResult: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let outputURLs: [URL]
    let pageCount: Int
    let processingTime: TimeInterval
}

// MARK: - Merge Options

struct MergeOptions {
    var outputDirectory: URL?
    var outputName: String = "merged"
    var addBookmarks: Bool = true
}

struct MergeResult: Identifiable {
    let id = UUID()
    let sourceURLs: [URL]
    let outputURL: URL
    let totalPages: Int
    let processingTime: TimeInterval
}

// MARK: - Rotate Options

enum RotationAngle: Int, CaseIterable, Identifiable {
    case clockwise90 = 90
    case clockwise180 = 180
    case counterclockwise90 = 270

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .clockwise90: return "90° Clockwise"
        case .clockwise180: return "180°"
        case .counterclockwise90: return "90° Counter-clockwise"
        }
    }

    var icon: String {
        switch self {
        case .clockwise90: return "rotate.right"
        case .clockwise180: return "arrow.2.squarepath"
        case .counterclockwise90: return "rotate.left"
        }
    }
}

struct RotateOptions {
    var angle: RotationAngle = .clockwise90
    var applyToAllPages: Bool = true
    var specificPages: [Int] = []
    var outputDirectory: URL?
    var customOutputName: String?
}

struct RotateResult: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let outputURL: URL
    let pagesRotated: Int
    let angle: RotationAngle
    let processingTime: TimeInterval
}

// MARK: - Signature Options

struct SavedSignature: Identifiable, Codable {
    let id: UUID
    let name: String
    let imageData: Data
    let createdAt: Date

    init(id: UUID = UUID(), name: String, imageData: Data, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.createdAt = createdAt
    }

    var image: NSImage? {
        NSImage(data: imageData)
    }
}

enum SignaturePosition: String, CaseIterable, Identifiable {
    case topLeft = "top_left"
    case topCenter = "top_center"
    case topRight = "top_right"
    case centerLeft = "center_left"
    case center = "center"
    case centerRight = "center_right"
    case bottomLeft = "bottom_left"
    case bottomCenter = "bottom_center"
    case bottomRight = "bottom_right"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .centerLeft: return "Center Left"
        case .center: return "Center"
        case .centerRight: return "Center Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        case .custom: return "Custom Position"
        }
    }
}

struct SignatureOptions {
    var signatureImage: NSImage?
    var position: SignaturePosition = .bottomRight
    var customX: CGFloat = 0
    var customY: CGFloat = 0
    var width: CGFloat = 150
    var height: CGFloat = 50
    var page: Int = 1 // 1-indexed
    var applyToAllPages: Bool = false
    var outputDirectory: URL?
    var customOutputName: String?
}

struct SignatureResult: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let outputURL: URL
    let pagesModified: Int
    let processingTime: TimeInterval
}

// MARK: - Security Options

struct SecurityOptions {
    var ownerPassword: String = ""
    var userPassword: String = ""
    var allowPrinting: Bool = true
    var allowCopying: Bool = false
    var allowModifying: Bool = false
    var allowAnnotating: Bool = true
    var outputDirectory: URL?
    var customOutputName: String?
}

struct SecurityResult: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let outputURL: URL
    let isEncrypted: Bool
    let processingTime: TimeInterval
}

// MARK: - Watermark Options

enum WatermarkType: String, CaseIterable, Identifiable {
    case text = "text"
    case image = "image"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return "Text Watermark"
        case .image: return "Image Watermark"
        }
    }
}

struct WatermarkOptions {
    var type: WatermarkType = .text
    var text: String = "CONFIDENTIAL"
    var image: NSImage?
    var opacity: CGFloat = 0.3
    var rotation: CGFloat = -45 // degrees
    var fontSize: CGFloat = 72
    var fontName: String = "Helvetica-Bold"
    var textColor: NSColor = .gray
    var position: SignaturePosition = .center
    var applyToAllPages: Bool = true
    var specificPages: [Int] = []
    var outputDirectory: URL?
    var customOutputName: String?
}

struct WatermarkResult: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let outputURL: URL
    let pagesModified: Int
    let processingTime: TimeInterval
}

// MARK: - Extract Pages Options

struct ExtractOptions {
    var pageRanges: String = ""
    var outputDirectory: URL?
    var outputName: String?
}

struct ExtractResult: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let outputURL: URL
    let pagesExtracted: Int
    let processingTime: TimeInterval
}
