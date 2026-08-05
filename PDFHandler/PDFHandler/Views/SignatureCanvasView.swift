//
//  SignatureCanvasView.swift
//  PDFHandler
//
//  Freehand signature drawing canvas. Strokes are captured as point
//  runs, drawn with midpoint-quad smoothing (so ink looks fluid, not
//  jagged), and rasterized on save to a transparent NSImage cropped
//  to the ink's bounding box.
//

import SwiftUI
import AppKit

struct SignatureCanvasView: View {
    /// Called once the user taps "Save". Nil means the canvas was empty.
    var onComplete: (NSImage?) -> Void
    var onCancel: () -> Void

    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []

    private let canvasSize = CGSize(width: 520, height: 200)
    private let inkWidth: CGFloat = 2.2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Draw your signature")
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    )

                // Baseline guide (not part of the saved image).
                Path { p in
                    p.move(to: CGPoint(x: 24, y: canvasSize.height * 0.72))
                    p.addLine(to: CGPoint(x: canvasSize.width - 24, y: canvasSize.height * 0.72))
                }
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                Canvas { ctx, _ in
                    for stroke in strokes {
                        drawStroke(stroke, in: &ctx)
                    }
                    drawStroke(currentStroke, in: &ctx)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        currentStroke.append(clamp(value.location))
                    }
                    .onEnded { _ in
                        if !currentStroke.isEmpty {
                            strokes.append(currentStroke)
                            currentStroke.removeAll()
                        }
                    }
            )

            HStack {
                Button("Clear") {
                    strokes.removeAll()
                    currentStroke.removeAll()
                }
                .disabled(strokes.isEmpty && currentStroke.isEmpty)

                Spacer()

                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save") { onComplete(render()) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(strokes.isEmpty)
            }
        }
        .padding(20)
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }

    private func drawStroke(_ stroke: [CGPoint], in ctx: inout GraphicsContext) {
        guard let first = stroke.first else { return }
        if stroke.count == 1 {
            // A plain click is a pen dot (i-dots, punctuation).
            let r = inkWidth * 0.7
            ctx.fill(
                Path(ellipseIn: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2)),
                with: .color(.black)
            )
            return
        }
        ctx.stroke(
            Path(Self.smoothedPath(stroke)),
            with: .color(.black),
            style: StrokeStyle(lineWidth: inkWidth, lineCap: .round, lineJoin: .round)
        )
    }

    /// Midpoint quad smoothing: curve through segment midpoints with
    /// the sampled points as controls.
    static func smoothedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(
                x: (points[i].x + points[i + 1].x) / 2,
                y: (points[i].y + points[i + 1].y) / 2
            )
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    private func render() -> NSImage? {
        guard !strokes.isEmpty else { return nil }

        // Crop to the ink's bounding box (plus margin) so the saved
        // asset carries no dead transparent borders — placement sizing
        // and aspect-fit then match what was actually drawn.
        let all = strokes.flatMap { $0 }
        guard let minX = all.map(\.x).min(),
              let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(),
              let maxY = all.map(\.y).max() else { return nil }
        let margin: CGFloat = 6
        let crop = CGRect(
            x: minX - margin,
            y: minY - margin,
            width: max(maxX - minX + margin * 2, 8),
            height: max(maxY - minY + margin * 2, 8)
        )

        let image = NSImage(size: crop.size)
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

        // Flip to top-left origin so canvas-space points draw directly.
        // Intentionally no background fill: the strokes float on
        // transparency instead of being boxed in a white card.
        ctx.translateBy(x: 0, y: crop.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -crop.minX, y: -crop.minY)

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setLineWidth(inkWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for stroke in strokes {
            guard let first = stroke.first else { continue }
            if stroke.count == 1 {
                let r = inkWidth * 0.7
                ctx.fillEllipse(in: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2))
                continue
            }
            ctx.addPath(Self.smoothedPath(stroke))
            ctx.strokePath()
        }
        return image
    }
}
