//
//  ZoomScale.swift
//  PDFHandler
//
//  Zoom limits and step arithmetic. Deliberately a free-standing,
//  non-isolated type rather than statics on AppState: this is pure
//  value math with no relationship to the main actor, and living
//  outside the @MainActor class keeps it directly testable.
//

import Foundation

enum ZoomScale {
    static let min: Double = 0.25
    static let max: Double = 6.0

    /// Levels the +/− buttons and the toolbar menu step through.
    static let stops: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 6.0]

    /// Next stop above `value`, saturating at the ceiling. The 0.5%
    /// tolerance absorbs float noise so landing exactly on a stop
    /// still advances rather than sticking.
    static func stop(above value: Double) -> Double {
        stops.first { $0 > value * 1.005 } ?? max
    }

    static func stop(below value: Double) -> Double {
        stops.last { $0 < value * 0.995 } ?? min
    }

    static func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}
