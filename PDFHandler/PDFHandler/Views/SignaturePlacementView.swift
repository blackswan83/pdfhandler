//
//  SignaturePlacementView.swift
//  PDFHandler
//
//  Renders the current PDF page and overlays a draggable, resizable
//  signature stamp. The parent receives the final placement in PDF
//  user-space points (bottom-left origin) for stamping.
//

import SwiftUI
import PDFKit
import AppKit

struct SignaturePlacement {
    /// PDF user-space rect (bottom-left origin, points).
    var pdfRect: CGRect
    /// 1-indexed page number.
    var page: Int
}

struct SignaturePlacementView: View {
    @Environment(\.colorScheme) var colorScheme

    let document: PDFDocument
    let signatureImage: NSImage
    @Binding var pageIndex: Int // 0-indexed

    /// View-space rect inside the rendered page (top-left origin).
    @State private var viewRect: CGRect = .zero

    /// Initial drag bookkeeping.
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var resizeDelta: CGSize = .zero

    /// Caller receives live placement updates so the "Sign" button stays in sync.
    var onPlacementChange: (SignaturePlacement) -> Void

    var body: some View {
        VStack(spacing: 10) {
            pageControls

            GeometryReader { geo in
                let page = document.page(at: pageIndex)
                let pageSize = page?.bounds(for: .mediaBox).size ?? CGSize(width: 612, height: 792)
                let fitted = fitRect(pageSize: pageSize, in: geo.size)

                ZStack {
                    // PDF page render
                    if page != nil {
                        PagePreview(document: document, pageIndex: pageIndex)
                            .frame(width: fitted.width, height: fitted.height)
                            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 2)
                            .allowsHitTesting(false)
                    }

                    // Floating signature stamp
                    let live = liveRect(in: fitted)
                    stamp(in: live, pageFrame: fitted)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                .onAppear { initializeRectIfNeeded(in: fitted, pageSize: pageSize) }
                .onChange(of: pageIndex) { _ in
                    resetRect(in: fitted, pageSize: pageSize)
                }
                .onChange(of: geo.size) { _ in
                    clampRect(in: fitted)
                }
                .onChange(of: viewRect) { _ in
                    publishPlacement(pageSize: pageSize, fitted: fitted)
                }
            }
        }
    }

    // MARK: Page controls

    private var pageControls: some View {
        HStack(spacing: 12) {
            Button(action: { pageIndex = max(0, pageIndex - 1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(pageIndex == 0)
            .foregroundStyle(pageIndex == 0 ? Color.stonegrey.opacity(0.4) : (colorScheme == .dark ? .white : Color.inkBlack))

            Text("page \(pageIndex + 1) / \(document.pageCount)")
                .font(SumiTypography.monoSmall)
                .foregroundStyle(Color.stonegrey)
                .frame(minWidth: 80)

            Button(action: { pageIndex = min(document.pageCount - 1, pageIndex + 1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(pageIndex >= document.pageCount - 1)
            .foregroundStyle(pageIndex >= document.pageCount - 1 ? Color.stonegrey.opacity(0.4) : (colorScheme == .dark ? .white : Color.inkBlack))

            Spacer()

            Text("drag to position · corner to resize")
                .font(SumiTypography.monoSmall)
                .foregroundStyle(Color.stonegrey)
        }
    }

    // MARK: Stamp

    private func stamp(in rect: CGRect, pageFrame: CGRect) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: signatureImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: rect.width, height: rect.height)

            // Resize handle
            Rectangle()
                .fill(accent)
                .frame(width: 12, height: 12)
                .offset(x: 6, y: 6)
                .highPriorityGesture(
                    DragGesture()
                        .updating($resizeDelta) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            let aspect = max(0.1, signatureImage.size.width / max(1, signatureImage.size.height))
                            var w = max(40, viewRect.width + value.translation.width)
                            w = min(w, pageFrame.width - (viewRect.minX - pageFrame.minX))
                            let h = max(20, w / aspect)
                            viewRect = CGRect(x: viewRect.minX, y: viewRect.minY, width: w, height: h)
                            clampRect(in: pageFrame)
                        }
                )
        }
        .overlay(
            Rectangle()
                .stroke(accent, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: rect.width, height: rect.height)
        )
        .position(x: rect.midX, y: rect.midY)
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    viewRect = viewRect.offsetBy(dx: value.translation.width, dy: value.translation.height)
                    clampRect(in: pageFrame)
                }
        )
    }

    // MARK: Layout helpers

    private func liveRect(in pageFrame: CGRect) -> CGRect {
        let aspect = max(0.1, signatureImage.size.width / max(1, signatureImage.size.height))
        var r = viewRect
            .offsetBy(dx: dragOffset.width, dy: dragOffset.height)
        // Apply in-flight resize
        let newWidth = max(40, viewRect.width + resizeDelta.width)
        let newHeight = max(20, newWidth / aspect)
        r = CGRect(x: r.minX, y: r.minY, width: newWidth, height: newHeight)
        // Clamp within page frame (loose)
        r.origin.x = max(pageFrame.minX, min(r.origin.x, pageFrame.maxX - r.width))
        r.origin.y = max(pageFrame.minY, min(r.origin.y, pageFrame.maxY - r.height))
        return r
    }

    private func fitRect(pageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard pageSize.width > 0, pageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let scale = min(containerSize.width / pageSize.width, containerSize.height / pageSize.height)
        let w = pageSize.width * scale
        let h = pageSize.height * scale
        let x = (containerSize.width - w) / 2
        let y = (containerSize.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func initializeRectIfNeeded(in pageFrame: CGRect, pageSize: CGSize) {
        guard viewRect == .zero, pageFrame.width > 0 else { return }
        resetRect(in: pageFrame, pageSize: pageSize)
    }

    private func resetRect(in pageFrame: CGRect, pageSize: CGSize) {
        guard pageFrame.width > 0 else { return }
        let aspect = max(0.1, signatureImage.size.width / max(1, signatureImage.size.height))
        // Default: 30% of page width, placed bottom-right with a margin.
        let w = min(pageFrame.width * 0.3, 240)
        let h = w / aspect
        let margin: CGFloat = 20
        let x = pageFrame.maxX - w - margin
        let y = pageFrame.maxY - h - margin
        viewRect = CGRect(x: x, y: y, width: w, height: h)
    }

    private func clampRect(in pageFrame: CGRect) {
        guard pageFrame.width > 0 else { return }
        var r = viewRect
        r.size.width = min(r.width, pageFrame.width)
        r.size.height = min(r.height, pageFrame.height)
        r.origin.x = max(pageFrame.minX, min(r.origin.x, pageFrame.maxX - r.width))
        r.origin.y = max(pageFrame.minY, min(r.origin.y, pageFrame.maxY - r.height))
        viewRect = r
    }

    private func publishPlacement(pageSize: CGSize, fitted: CGRect) {
        guard fitted.width > 0, fitted.height > 0 else { return }
        let scale = pageSize.width / fitted.width
        // Convert view-space (top-left origin) → PDF user-space (bottom-left origin)
        let x = (viewRect.minX - fitted.minX) * scale
        let yTopLeft = (viewRect.minY - fitted.minY) * scale
        let w = viewRect.width * scale
        let h = viewRect.height * scale
        let y = pageSize.height - yTopLeft - h
        onPlacementChange(
            SignaturePlacement(
                pdfRect: CGRect(x: x, y: y, width: w, height: h),
                page: pageIndex + 1
            )
        )
    }

    private var accent: Color {
        colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen
    }
}

// MARK: - PDF page preview

private struct PagePreview: NSViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displaysPageBreaks = false
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
        if let page = document.page(at: pageIndex), view.currentPage !== page {
            view.go(to: page)
        }
    }
}
