//
//  ScreenshotDemo.swift
//  PDFHandler
//
//  Development scaffolding. Launching with `--screenshot-demo` fills
//  the app with a synthetic agreement, a synthetic signature library
//  and a few placed fields, so CI can photograph a populated UI
//  instead of an empty-state window.
//
//  Nothing here runs unless that argument is present, and the library
//  is seeded in memory only — a real user's saved signatures are never
//  touched.
//

import Foundation
import SwiftUI
import PDFKit
import AppKit
import CoreText

enum ScreenshotDemo {

    static var isEnabled: Bool {
        CommandLine.arguments.contains("--screenshot-demo")
    }

    /// `--screenshot-mode compress` selects a tab deterministically.
    /// Driving the sidebar through accessibility automation instead
    /// proved unreliable — the click silently did nothing and CI
    /// captured the same pane twice.
    static var initialMode: AppMode? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--screenshot-mode"),
              args.index(after: flag) < args.endIndex
        else { return nil }
        return AppMode(rawValue: args[args.index(after: flag)])
    }

    /// Draws a plausible two-page consulting agreement into a temp file
    /// so the preview has real page content to render.
    static func writeSampleAgreement() -> URL? {
        let pageSize = CGSize(width: 612, height: 792)   // US Letter
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Consulting Agreement.pdf")

        guard let ctx = CGContext(url as CFURL, mediaBox: nil, nil) else { return nil }

        for pageNumber in 1...2 {
            var box = CGRect(origin: .zero, size: pageSize)
            ctx.beginPage(mediaBox: &box)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(box)

            var y = pageSize.height - 96.0

            if pageNumber == 1 {
                draw("CONSULTING AGREEMENT", at: CGPoint(x: 72, y: y), size: 20, weight: .bold, in: ctx)
                y -= 34
                draw("This Agreement is entered into as of the date last signed below,",
                     at: CGPoint(x: 72, y: y), size: 10.5, in: ctx)
                y -= 16
                draw("by and between the parties identified in Schedule A.",
                     at: CGPoint(x: 72, y: y), size: 10.5, in: ctx)
                y -= 30
            } else {
                draw("SCHEDULE A — SCOPE OF SERVICES", at: CGPoint(x: 72, y: y), size: 14, weight: .semibold, in: ctx)
                y -= 30
            }

            // Body text: real glyphs rather than grey bars, so the
            // preview's rendering quality is actually visible.
            let paragraph = [
                "1.  Services. The Consultant shall provide the services described in",
                "     Schedule A, exercising reasonable skill and care, and shall report",
                "     progress to the Client at intervals agreed between the parties.",
                "",
                "2.  Term. This Agreement commences on the Effective Date and continues",
                "     until terminated by either party on thirty (30) days written notice.",
                "",
                "3.  Fees. The Client shall pay the fees set out in Schedule A within",
                "     thirty (30) days of receipt of a valid invoice.",
                "",
                "4.  Confidentiality. Each party shall keep confidential all information",
                "     disclosed by the other and marked or reasonably understood to be",
                "     confidential, and shall not disclose it to any third party.",
                "",
                "5.  Intellectual Property. All deliverables prepared by the Consultant",
                "     under this Agreement vest in the Client upon payment in full.",
            ]
            for line in paragraph {
                draw(line, at: CGPoint(x: 72, y: y), size: 10, in: ctx)
                y -= 15
            }

            if pageNumber == 1 {
                y -= 40
                draw("Signed for and on behalf of the Consultant:",
                     at: CGPoint(x: 72, y: y), size: 10, in: ctx)
                y -= 46
                rule(from: CGPoint(x: 72, y: y), width: 200, in: ctx)
                rule(from: CGPoint(x: 330, y: y), width: 160, in: ctx)
                draw("Signature", at: CGPoint(x: 72, y: y - 14), size: 8.5, in: ctx)
                draw("Date", at: CGPoint(x: 330, y: y - 14), size: 8.5, in: ctx)

                y -= 52
                draw("Company name:", at: CGPoint(x: 72, y: y), size: 10, in: ctx)
                rule(from: CGPoint(x: 160, y: y - 4), width: 240, in: ctx)

                y -= 34
                draw("I have read and accept the terms above.",
                     at: CGPoint(x: 96, y: y), size: 10, in: ctx)
            }

            draw("Page \(pageNumber) of 2", at: CGPoint(x: 72, y: 48), size: 8.5, in: ctx)
            ctx.endPage()
        }
        ctx.closePDF()

        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func draw(
        _ text: String,
        at point: CGPoint,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        in ctx: CGContext
    ) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.black.cgColor,
        ])
        let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

    private static func rule(from point: CGPoint, width: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1))
        ctx.setLineWidth(0.75)
        ctx.move(to: point)
        ctx.addLine(to: CGPoint(x: point.x + width, y: point.y))
        ctx.strokePath()
        ctx.restoreGState()
    }
}

extension AppState {

    /// Populate the app with the demo document, library and placements.
    /// Called from ContentView.onAppear when --screenshot-demo is set.
    func loadScreenshotDemo() {
        // Library first: openDocument clears placements, and the
        // placements below need a signature ID to reference.
        let signature = NewSignatureView.renderTypedSignature("Alex Marchetti", font: .elegant)
        let initials  = NewSignatureView.renderTypedSignature("AM", font: .elegant)
        var entries: [SavedSignature] = []
        if let data = signature.pngData() {
            entries.append(SavedSignature(name: "Alex Marchetti", imageData: data, role: .signature))
        }
        if let data = initials.pngData() {
            entries.append(SavedSignature(name: "AM", imageData: data, role: .initials))
        }
        replaceLibraryInMemory(entries)

        guard let url = ScreenshotDemo.writeSampleAgreement() else { return }
        openDocument(at: url)

        guard let signatureID = activeSignatureID else { return }

        let formatter = DateFormatter()
        formatter.dateStyle = .long

        // Positioned onto the ruled signature block drawn above.
        let placed: [Placement] = [
            Placement(
                content: .signature(signatureID: signatureID),
                pageIndex: 0,
                normalizedRect: CGRect(x: 0.115, y: 0.640, width: 0.30, height: 0.055)
            ),
            Placement(
                content: .date(text: formatter.string(from: Date())),
                pageIndex: 0,
                normalizedRect: CGRect(x: 0.540, y: 0.652, width: 0.235, height: 0.026)
            ),
            Placement(
                content: .freeText(text: "Nuraxi Ltd"),
                pageIndex: 0,
                normalizedRect: CGRect(x: 0.265, y: 0.716, width: 0.30, height: 0.026)
            ),
            Placement(
                content: .checkbox(isChecked: true),
                pageIndex: 0,
                normalizedRect: CGRect(x: 0.128, y: 0.760, width: 0.022, height: 0.017)
            ),
        ]
        placements = placed
        // Select the signature so the screenshot shows the selection
        // chrome — border, resize knob and delete button.
        selectedPlacementID = placed.first?.id
    }
}
