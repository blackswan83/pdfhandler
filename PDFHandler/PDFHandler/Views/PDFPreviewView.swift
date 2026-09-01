//
//  PDFPreviewView.swift
//  PDFHandler
//
//  Shows the current page rendered to a cached bitmap and overlays any
//  placements for that page. Clicking empty space drops a new
//  placement using the active tool.
//
//  Zoom model: the page is drawn at `pageSize × scale`, where scale is
//  either the fit-to-window scale or an absolute user-chosen zoom.
//  Because placements are stored in normalized page coordinates and
//  are laid out against that same scaled size, zooming is transparent
//  to every gesture — while the chrome (resize knob, delete button)
//  keeps a constant on-screen size, the way a design tool should.
//

import SwiftUI
import PDFKit
import AppKit

struct PDFPreviewView: View {
    @EnvironmentObject var appState: AppState

    /// Stable coordinate space for placement drag gestures. Measuring
    /// drags here (instead of in the moving placement's own space)
    /// is what keeps moves and resizes steady.
    static let pageSpaceName = "pdfhandler.pageSpace"

    /// Identity of the invisible marker that zoom keeps centered.
    private static let zoomAnchorID = "pdfhandler.zoomAnchor"

    /// Breathing room around the page inside the scroll area.
    private static let pageMargin: CGFloat = 16

    /// Ceiling on the rasterized page bitmap's longest edge. At extreme
    /// zoom the bitmap is upscaled slightly rather than allocating
    /// hundreds of megabytes per page.
    private static let maxRasterPixels: CGFloat = 4096

    @State private var pinchBaseline: Double?

    var body: some View {
        GeometryReader { geo in
            if let pdf = appState.document, pdf.pageCount > 0 {
                let pageIndex = clampedPageIndex(pageCount: pdf.pageCount)
                if let page = pdf.page(at: pageIndex) {
                    let pageSize = page.displaySize
                    let fitted = fitScale(pageSize: pageSize, container: geo.size)
                    let scale = appState.isZoomFitted ? fitted : CGFloat(appState.zoom)
                    let display = CGSize(
                        width: pageSize.width * scale,
                        height: pageSize.height * scale
                    )

                    zoomableContent(
                        page: page,
                        pageIndex: pageIndex,
                        display: display,
                        pageScale: scale,
                        viewport: geo.size
                    )
                    .onAppear { appState.recordFittedScale(Double(fitted)) }
                    .onChange(of: fitted) { appState.recordFittedScale(Double($0)) }
                }
            } else {
                emptyState
            }
        }
    }

    // MARK: - Scrollable, zoomable page

    private func zoomableContent(
        page: PDFPage,
        pageIndex: Int,
        display: CGSize,
        pageScale: CGFloat,
        viewport: CGSize
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                pageStack(page: page, pageIndex: pageIndex, display: display)
                    .padding(Self.pageMargin)
                    // Lower bound only: a page larger than the viewport
                    // keeps its natural size and scrolls; a smaller one
                    // expands to the viewport and centers.
                    .frame(minWidth: viewport.width, minHeight: viewport.height)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: appState.zoomToken) { _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(Self.zoomAnchorID, anchor: .center)
                }
            }
        }
        .gesture(pinchZoom(currentScale: pageScale))
    }

    private func pageStack(page: PDFPage, pageIndex: Int, display: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: pageImage(page: page, pageIndex: pageIndex, display: display))
                .resizable()
                .interpolation(.high)
                .frame(width: display.width, height: display.height)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)

            // Click-to-place hit layer, behind the placement overlays.
            Color.white.opacity(0.001)
                .frame(width: display.width, height: display.height)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { event in
                            handlePageClick(location: event.location, pageSize: display)
                        }
                )

            ForEach(appState.placements(onPage: pageIndex)) { placement in
                PlacementView(
                    placement: placement,
                    pageSize: display,
                    pageScale: page.displaySize.width > 0
                        ? display.width / page.displaySize.width : 1
                )
                .environmentObject(appState)
            }
        }
        .frame(width: display.width, height: display.height)
        .overlay(alignment: .topLeading) {
            zoomAnchor(display: display, pageIndex: pageIndex)
        }
        .coordinateSpace(name: Self.pageSpaceName)
    }

    /// A 1×1 invisible marker sitting at the point zoom should keep in
    /// view: the selected field if there is one, otherwise the page
    /// center. Positioned with `.padding` rather than `.offset` because
    /// ScrollViewReader scrolls to *layout* frames, and `.offset` moves
    /// only the rendering.
    private func zoomAnchor(display: CGSize, pageIndex: Int) -> some View {
        let focus = zoomFocusPoint(display: display, pageIndex: pageIndex)
        return Color.clear
            .frame(width: 1, height: 1)
            .padding(.leading, min(max(focus.x, 0), max(0, display.width - 1)))
            .padding(.top, min(max(focus.y, 0), max(0, display.height - 1)))
            .id(Self.zoomAnchorID)
            .allowsHitTesting(false)
    }

    private func zoomFocusPoint(display: CGSize, pageIndex: Int) -> CGPoint {
        if let id = appState.selectedPlacementID,
           let placement = appState.placements.first(where: { $0.id == id }),
           placement.pageIndex == pageIndex {
            return CGPoint(
                x: placement.normalizedRect.midX * display.width,
                y: placement.normalizedRect.midY * display.height
            )
        }
        return CGPoint(x: display.width / 2, y: display.height / 2)
    }

    private func pinchZoom(currentScale: CGFloat) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let base = pinchBaseline ?? Double(currentScale)
                if pinchBaseline == nil { pinchBaseline = base }
                appState.setZoom(base * Double(value), recenter: false)
            }
            .onEnded { _ in pinchBaseline = nil }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Open a PDF to start signing")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Open PDF…") {
                NotificationCenter.default.post(name: .requestOpenPanel, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
            Text("Or drag one anywhere into this window — from Finder,\nor an attachment straight out of Mail.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rendering

    private func pageImage(page: PDFPage, pageIndex: Int, display: CGSize) -> NSImage {
        let pageSize = page.displaySize
        guard display.width >= 1, display.height >= 1,
              pageSize.width > 0, pageSize.height > 0
        else { return NSImage(size: NSSize(width: 1, height: 1)) }

        // Render at the window's actual backing scale (mixed-DPI safe),
        // bucketing the pixel width so live window resizing and small
        // zoom nudges reuse a cached bitmap instead of re-rasterizing.
        let backing = NSApp.keyWindow?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2
        var pixelW = (display.width * backing / 128).rounded(.up) * 128
        var pixelH = (pixelW * pageSize.height / pageSize.width).rounded()

        let longest = max(pixelW, pixelH)
        if longest > Self.maxRasterPixels {
            let k = Self.maxRasterPixels / longest
            pixelW = (pixelW * k).rounded()
            pixelH = (pixelH * k).rounded()
        }
        let pixel = CGSize(width: max(1, pixelW), height: max(1, pixelH))

        return PageImageCache.shared.image(
            documentID: appState.documentID,
            pageIndex: pageIndex,
            pixelSize: pixel
        ) {
            page.renderedDisplayImage(pixelSize: pixel, pointSize: pixel)
                ?? NSImage(size: NSSize(width: 1, height: 1))
        }
    }

    /// Scale at which the whole page fits the viewport, with margins.
    private func fitScale(pageSize: CGSize, container: CGSize) -> CGFloat {
        guard pageSize.width > 0, pageSize.height > 0,
              container.width > 0, container.height > 0 else { return 1 }
        // Margin on both sides, plus a couple of points of slack so a
        // fitted page never sits exactly at the viewport size and
        // flickers scrollbars.
        let inset = Self.pageMargin * 2 + 4
        let scale = min(
            (container.width  - inset) / pageSize.width,
            (container.height - inset) / pageSize.height
        )
        return max(scale, 0.05)
    }

    private func clampedPageIndex(pageCount: Int) -> Int {
        min(max(appState.currentPageIndex, 0), pageCount - 1)
    }

    // MARK: - Click to place

    private func handlePageClick(location: CGPoint, pageSize: CGSize) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }

        // A click outside the field being edited just ends the edit —
        // it should not also drop a brand-new field.
        if appState.editingPlacementID != nil {
            appState.editingPlacementID = nil
            return
        }

        // Signature / initials tool armed but the library is empty:
        // guide the user to create one instead of doing nothing.
        if appState.activeTool == .signature, appState.activeSignatureID == nil {
            appState.newSignatureRole = .signature
            appState.isPresentingNewSignature = true
            return
        }
        if appState.activeTool == .initials, appState.activeInitialsID == nil {
            appState.newSignatureRole = .initials
            appState.isPresentingNewSignature = true
            return
        }

        let normalized = CGPoint(
            x: min(max(location.x / pageSize.width, 0), 1),
            y: min(max(location.y / pageSize.height, 0), 1)
        )
        appState.addPlacement(at: normalized)
    }
}
