//
//  SignatureCanvasView.swift
//  PDFHandler
//
//  Freehand signature drawing canvas. Tracks strokes as paths and
//  produces a rasterized NSImage on save (white background, black ink).
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

                Canvas { ctx, _ in
                    for stroke in strokes {
                        drawStroke(stroke, in: &ctx)
                    }
                    drawStroke(currentStroke, in: &ctx)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        currentStroke.append(value.location)
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

    private func drawStroke(_ stroke: [CGPoint], in ctx: inout GraphicsContext) {
        guard stroke.count > 1 else { return }
        var path = Path()
        path.move(to: stroke[0])
        for point in stroke.dropFirst() {
            path.addLine(to: point)
        }
        ctx.stroke(path, with: .color(.black),
                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }

    private func render() -> NSImage? {
        guard !strokes.isEmpty else { return nil }

        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        // SwiftUI coordinates have origin at top-left; NSImage (flipped=false)
        // has origin at bottom-left. Mirror Y so strokes land correctly.
        let path = NSBezierPath()
        path.lineWidth = 2.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        for stroke in strokes where stroke.count > 1 {
            path.move(to: NSPoint(x: stroke[0].x, y: canvasSize.height - stroke[0].y))
            for point in stroke.dropFirst() {
                path.line(to: NSPoint(x: point.x, y: canvasSize.height - point.y))
            }
        }
        NSColor.black.setStroke()
        path.stroke()

        return image
    }
}
