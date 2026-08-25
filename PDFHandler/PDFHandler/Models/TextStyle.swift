//
//  TextStyle.swift
//  PDFHandler
//
//  Typography for the text-bearing placements (free text and date).
//
//  `size` is always in PAGE POINTS, never screen points, so a field
//  keeps its size when the window is resized or zoomed, and the
//  preview matches the burned-in output exactly. The preview
//  multiplies by the current page scale; the flattener uses it raw.
//

import Foundation
import CoreGraphics
import AppKit

enum TextFont: String, CaseIterable, Identifiable, Equatable {
    case system, helvetica, times, courier, georgia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:    return "System"
        case .helvetica: return "Helvetica"
        case .times:     return "Times"
        case .courier:   return "Courier"
        case .georgia:   return "Georgia"
        }
    }

    /// PostScript name, or nil for the system font.
    var postScriptName: String? {
        switch self {
        case .system:    return nil
        case .helvetica: return "Helvetica"
        case .times:     return "TimesNewRomanPSMT"
        case .courier:   return "Courier"
        case .georgia:   return "Georgia"
        }
    }

    /// Resolved NSFont, falling back to the system font when the face
    /// is missing so text never silently disappears from an export.
    func nsFont(size: CGFloat) -> NSFont {
        guard let name = postScriptName, let font = NSFont(name: name, size: size) else {
            return NSFont.systemFont(ofSize: size)
        }
        return font
    }
}

struct TextStyle: Equatable {
    var font: TextFont
    /// Point size used when `autoFit` is off.
    var size: CGFloat
    /// Derive the size from the box height instead, so the text grows
    /// and shrinks as the box is resized.
    var autoFit: Bool

    static let `default` = TextStyle(font: .system, size: 12, autoFit: true)

    static let minSize: CGFloat = 4
    static let maxSize: CGFloat = 96

    /// The size to actually draw at, given the box height in the same
    /// coordinate space the caller wants back.
    func resolvedSize(boxHeight: CGFloat) -> CGFloat {
        guard autoFit else { return min(max(size, Self.minSize), Self.maxSize) }
        return max(Self.minSize, boxHeight * PDFFlattener.Style.textFontFactor)
    }
}
