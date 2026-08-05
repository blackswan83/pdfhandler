//
//  PlacementView.swift
//  PDFHandler
//
//  A single draggable / resizable field on the PDF preview.
//
//  Interaction model (DocuSign-style):
//    • click        → select (checkboxes also toggle)
//    • drag         → move
//    • corner knob  → resize (aspect kept for images / checkboxes;
//                     text fields resize freely and their font scales
//                     with the box height)
//    • double-click → edit text inline (date / free text)
//    • ⌫ / Esc / arrows are handled by SignWorkspaceView's key monitor
//
//  All drag gestures are measured in the page's named coordinate
//  space. A gesture measured in the moving view's own space feeds its
//  own translation back into itself — that feedback loop is what made
//  resizing "shake all over the screen" before.
//

import SwiftUI
import AppKit

struct PlacementView: View {
    let placement: Placement
    let pageSize: CGSize
    @EnvironmentObject var appState: AppState

    @State private var dragStart: CGRect?
    @State private var preDragPlacements: [Placement]?
    @State private var isHovering = false
    @State private var draft: String = ""
    @FocusState private var textFocused: Bool

    private var pixelRect: CGRect {
        CGRect(
            x: placement.normalizedRect.origin.x * pageSize.width,
            y: placement.normalizedRect.origin.y * pageSize.height,
            width: placement.normalizedRect.width * pageSize.width,
            height: placement.normalizedRect.height * pageSize.height
        )
    }

    private var isSelected: Bool {
        appState.selectedPlacementID == placement.id
    }

    private var isEditing: Bool {
        appState.editingPlacementID == placement.id
    }

    private var showsControls: Bool {
        isSelected || isHovering || dragStart != nil
    }

    var body: some View {
        let rect = pixelRect

        content(rect: rect)
            .frame(width: rect.width, height: rect.height)
            .clipped()
            .overlay(border)
            .contentShape(Rectangle())
            // ORDER MATTERS: .position turns its subject into a parent-
            // filling layout. Any .overlay / .gesture / .contextMenu
            // applied *after* .position attaches to the whole PDF
            // preview area, not the placement's frame. Keep all
            // interactive modifiers BEFORE .position.
            .overlay(alignment: .bottomTrailing) {
                if showsControls { resizeHandle }
            }
            .overlay(alignment: .topTrailing) {
                if showsControls { deleteButton }
            }
            .contextMenu {
                Button("Apply to every page") { appState.applyToEveryPage(id: placement.id) }
                Divider()
                Button(role: .destructive) {
                    appState.removePlacement(id: placement.id)
                } label: { Label("Delete", systemImage: "trash") }
            }
            .simultaneousGesture(editTap)
            .simultaneousGesture(selectTap)
            .gesture(bodyDrag, including: isEditing ? .subviews : .all)
            .onHover { hovering in
                isHovering = hovering
                guard !isEditing else { return }
                if hovering, dragStart == nil {
                    NSCursor.openHand.set()
                } else if !hovering, dragStart == nil {
                    NSCursor.arrow.set()
                }
            }
            .position(x: rect.midX, y: rect.midY)
            .onAppear {
                // A freshly dropped, still-empty text box goes straight
                // into editing so the user can just start typing.
                if case .freeText(let text) = placement.content, text.isEmpty, isSelected {
                    appState.editingPlacementID = placement.id
                }
            }
    }

    // MARK: - Content dispatch

    @ViewBuilder
    private func content(rect: CGRect) -> some View {
        switch placement.content {
        case .signature(let id), .initials(let id):
            if let image = appState.signature(id: id)?.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.gray.opacity(0.2)
            }

        case .date(let text):
            textContent(text, rect: rect) {
                appState.updateContentLive(id: placement.id, content: .date(text: $0))
            }

        case .freeText(let text):
            textContent(text, rect: rect) {
                appState.updateContentLive(id: placement.id, content: .freeText(text: $0))
            }

        case .checkbox(let isChecked):
            CheckboxGlyph(isChecked: isChecked)
        }
    }

    /// Same font / inset math as PDFFlattener so the preview is
    /// WYSIWYG with the burned-in output.
    @ViewBuilder
    private func textContent(
        _ text: String,
        rect: CGRect,
        onEdit: @escaping (String) -> Void
    ) -> some View {
        let fontSize = max(8, rect.height * PDFFlattener.Style.textFontFactor)
        let inset = rect.height * PDFFlattener.Style.textInsetFactor

        if isEditing {
            TextField("Text", text: Binding(
                get: { draft },
                set: { draft = $0; onEdit($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: fontSize))
            .foregroundStyle(Color.black)
            .padding(.horizontal, inset)
            .focused($textFocused)
            .onSubmit { appState.editingPlacementID = nil }
            .onExitCommand { appState.editingPlacementID = nil }
            .onAppear {
                draft = text
                DispatchQueue.main.async { textFocused = true }
            }
            .onChange(of: textFocused) { focused in
                if !focused, isEditing {
                    appState.editingPlacementID = nil
                }
            }
        } else {
            Text(text.isEmpty ? "Text" : text)
                .font(.system(size: fontSize))
                .foregroundStyle(text.isEmpty ? Color.gray.opacity(0.65) : Color.black)
                .lineLimit(1)
                .padding(.horizontal, inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: - Chrome

    private var border: some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(
                isSelected
                    ? Color.accentColor
                    : isHovering
                        ? Color.accentColor.opacity(0.6)
                        : Color.accentColor.opacity(placement.content.isImageBacked ? 0 : 0.35),
                style: StrokeStyle(
                    lineWidth: isSelected ? 1.5 : 1,
                    dash: isSelected || placement.content.isImageBacked ? [] : [4, 3]
                )
            )
    }

    private var deleteButton: some View {
        Button {
            appState.removePlacement(id: placement.id)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.red)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
        .help("Delete")
        .offset(x: 9, y: -9)
    }

    private var resizeHandle: some View {
        // Small design-tool corner knob centered on the corner. The hit
        // padding is kept modest so that at minimum field sizes the
        // knob doesn't eat drags meant to move the field.
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: 11, height: 11)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            .padding(6)
            .contentShape(Rectangle())
            .onHover { hovering in
                guard dragStart == nil else { return }
                if hovering {
                    NSCursor.crosshair.set()
                } else if isHovering, !isEditing {
                    // Back over the field body: the body's own onHover
                    // won't re-fire (the pointer never left it), so
                    // restore the move cursor here.
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .highPriorityGesture(resizeDrag)
            .offset(x: 12, y: 12)
    }

    // MARK: - Gestures

    private var selectTap: some Gesture {
        SpatialTapGesture().onEnded { event in
            appState.selectedPlacementID = placement.id
            if case .checkbox(let isChecked) = placement.content {
                // A press on the resize knob's corner also arrives here
                // (simultaneous gestures bypass the knob's exclusivity);
                // don't treat it as a toggle.
                let rect = pixelRect
                let knobZone = CGRect(x: rect.width - 16, y: rect.height - 16, width: 32, height: 32)
                if showsControls, knobZone.contains(event.location) { return }
                appState.updateContent(id: placement.id, content: .checkbox(isChecked: !isChecked))
            }
        }
    }

    private var editTap: some Gesture {
        TapGesture(count: 2).onEnded {
            guard placement.content.isTextEditable else { return }
            appState.selectedPlacementID = placement.id
            appState.editingPlacementID = placement.id
        }
    }

    private var bodyDrag: some Gesture {
        // minimumDistance leaves plain clicks for selection; the named
        // coordinate space keeps the translation stable while the view
        // itself moves.
        DragGesture(minimumDistance: 3, coordinateSpace: .named(PDFPreviewView.pageSpaceName))
            .onChanged { value in
                if dragStart == nil {
                    dragStart = pixelRect
                    preDragPlacements = appState.placements
                    appState.selectedPlacementID = placement.id
                    NSCursor.closedHand.set()
                }
                guard let start = dragStart else { return }
                emitLive(
                    origin: CGPoint(
                        x: start.origin.x + value.translation.width,
                        y: start.origin.y + value.translation.height
                    ),
                    size: start.size
                )
            }
            .onEnded { _ in finishDrag(label: "Move") }
    }

    private var resizeDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(PDFPreviewView.pageSpaceName))
            .onChanged { value in
                if dragStart == nil {
                    dragStart = pixelRect
                    preDragPlacements = appState.placements
                    appState.selectedPlacementID = placement.id
                }
                guard let start = dragStart else { return }
                let keepAspect = placement.content.keepsAspectRatio
                let minSide: CGFloat = 18
                let proposedW = max(minSide, start.width + value.translation.width)
                var newW = min(proposedW, pageSize.width)

                let newH: CGFloat
                if keepAspect, start.height > 0 {
                    let aspect = start.width / start.height
                    newH = min(newW / aspect, pageSize.height)
                    newW = newH * aspect
                } else {
                    let proposedH = max(minSide, start.height + value.translation.height)
                    newH = min(proposedH, pageSize.height)
                }
                // Fields pinned against the right/bottom page edge can
                // still grow: the origin shifts back to make room
                // instead of the size silently capping at the edge.
                let origin = CGPoint(
                    x: min(start.origin.x, pageSize.width - newW),
                    y: min(start.origin.y, pageSize.height - newH)
                )
                emitLive(origin: origin, size: CGSize(width: newW, height: newH))
            }
            .onEnded { _ in finishDrag(label: "Resize") }
    }

    private func finishDrag(label: String) {
        if let before = preDragPlacements {
            appState.finishInteraction(label: label, before: before)
        }
        dragStart = nil
        preDragPlacements = nil
        appState.commitPlacementSize(id: placement.id)
        NSCursor.arrow.set()
    }

    // MARK: - Normalize + emit

    private func emitLive(origin: CGPoint, size: CGSize) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        let clampedX = min(max(origin.x, 0), max(0, pageSize.width - size.width))
        let clampedY = min(max(origin.y, 0), max(0, pageSize.height - size.height))
        let normalized = CGRect(
            x: clampedX / pageSize.width,
            y: clampedY / pageSize.height,
            width: size.width / pageSize.width,
            height: size.height / pageSize.height
        )
        appState.updatePlacementLive(id: placement.id, normalizedRect: normalized)
    }
}

/// Vector checkbox drawn with the same proportions as the flattener's
/// burn-in (PDFFlattener.drawCheckbox, y-flipped) so what the user
/// approves on screen is exactly what lands in the saved PDF.
private struct CheckboxGlyph: View {
    let isChecked: Bool

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            guard side > 1 else { return }
            let inset = max(0.5, side * 0.08)
            let box = CGRect(
                x: (size.width - side) / 2 + inset,
                y: (size.height - side) / 2 + inset,
                width: side - inset * 2,
                height: side - inset * 2
            )
            ctx.stroke(
                Path(roundedRect: box, cornerRadius: side * 0.08),
                with: .color(.black),
                lineWidth: max(0.75, side * 0.05)
            )
            if isChecked {
                var check = Path()
                check.move(to: CGPoint(x: box.minX + box.width * 0.18, y: box.minY + box.height * 0.48))
                check.addLine(to: CGPoint(x: box.minX + box.width * 0.42, y: box.minY + box.height * 0.70))
                check.addLine(to: CGPoint(x: box.minX + box.width * 0.82, y: box.minY + box.height * 0.28))
                ctx.stroke(
                    check,
                    with: .color(.black),
                    style: StrokeStyle(lineWidth: max(1, side * 0.09), lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}
