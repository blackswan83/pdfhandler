//
//  Placement.swift
//  PDFHandler
//
//  A generic placeable field the user has dropped onto a PDF page.
//  Signatures, initials, typed date stamps, free-text boxes and
//  checkboxes all share the same drag/resize overlay and burn-in
//  path — they differ only in the `content` payload.
//

import Foundation
import CoreGraphics

/// What a placement actually contains. Signatures / initials reference
/// a library image; date / freeText hold inline text; checkbox holds
/// a boolean. Text kinds render at a font size derived from the box
/// height (in both preview and burn-in), so resizing the box resizes
/// the text.
enum PlacementContent: Equatable {
    case signature(signatureID: UUID)
    case initials(signatureID: UUID)
    case date(text: String, style: TextStyle)
    case freeText(text: String, style: TextStyle)
    case checkbox(isChecked: Bool)

    /// Text and typography of the text-bearing kinds, nil otherwise.
    var textPayload: (text: String, style: TextStyle)? {
        switch self {
        case .date(let text, let style), .freeText(let text, let style):
            return (text, style)
        default:
            return nil
        }
    }

    /// The same content with a new style; a no-op for non-text kinds.
    func withStyle(_ style: TextStyle) -> PlacementContent {
        switch self {
        case .date(let text, _):     return .date(text: text, style: style)
        case .freeText(let text, _): return .freeText(text: text, style: style)
        default:                     return self
        }
    }

    /// The same content with new text; a no-op for non-text kinds.
    func withText(_ text: String) -> PlacementContent {
        switch self {
        case .date(_, let style):     return .date(text: text, style: style)
        case .freeText(_, let style): return .freeText(text: text, style: style)
        default:                      return self
        }
    }

    var isImageBacked: Bool {
        switch self {
        case .signature, .initials: return true
        default: return false
        }
    }

    /// Whether resizing should preserve the box's aspect ratio.
    /// Image-backed kinds keep the asset's aspect; checkboxes stay
    /// square.
    var keepsAspectRatio: Bool {
        switch self {
        case .signature, .initials, .checkbox: return true
        default: return false
        }
    }

    var isTextEditable: Bool {
        switch self {
        case .date, .freeText: return true
        default: return false
        }
    }

    var referencedSignatureID: UUID? {
        switch self {
        case .signature(let id), .initials(let id): return id
        default: return nil
        }
    }
}

/// A single placed field on a PDF page. Coordinates are normalized
/// 0…1 against the page's displayed bounds so the same placement
/// renders correctly at any preview scale and maps cleanly to PDF
/// coordinates at export time. Top-left origin (SwiftUI convention);
/// the flattener flips Y when writing to PDF space.
struct Placement: Identifiable, Equatable {
    let id: UUID
    var content: PlacementContent
    var pageIndex: Int           // 0-based
    var normalizedRect: CGRect   // top-left origin, 0…1

    init(
        id: UUID = UUID(),
        content: PlacementContent,
        pageIndex: Int,
        normalizedRect: CGRect
    ) {
        self.id = id
        self.content = content
        self.pageIndex = pageIndex
        self.normalizedRect = normalizedRect
    }
}

/// The tool the user currently has "picked up". The next click on a
/// PDF page drops a placement of the matching kind.
enum FieldTool: String, CaseIterable, Identifiable, Hashable {
    case signature
    case initials
    case date
    case freeText
    case checkbox

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .signature: return "Signature"
        case .initials:  return "Initials"
        case .date:      return "Date"
        case .freeText:  return "Free text"
        case .checkbox:  return "Checkbox"
        }
    }

    var systemImage: String {
        switch self {
        case .signature: return "signature"
        case .initials:  return "textformat.abc"
        case .date:      return "calendar"
        case .freeText:  return "text.cursor"
        case .checkbox:  return "checkmark.square"
        }
    }
}
