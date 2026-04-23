//
//  PlacementView.swift
//  PDFHandler
//
//  A single dragged/resizable field on the PDF preview. Dispatches on
//  the placement's content kind: image-backed entries (signature,
//  initials) render the library NSImage; date / freeText render
//  inline Text; checkbox renders a toggleable symbol. Regardless of
//  kind, drag moves the body, drag on the bottom-right handle
//  resizes (aspect ratio kept for image-backed kinds).
//

import SwiftUI
import AppKit

struct PlacementView: View {
    let placement: Placement
    let pageSize: CGSize
    @EnvironmentObject var appState: AppState

    @State private var dragStart: CGRect?
    @State private var editingText: String = ""

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

    var body: some View {
        let rect = pixelRect

        ZStack(alignment: .topTrailing) {
            content
                .frame(width: rect.width, height: rect.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? Color.accentColor : Color.accentColor.opacity(0.45),
                                lineWidth: isSelected ? 1.5 : 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { appState.selectedPlacementID = placement.id }

            Button(action: { appState.removePlacement(id: placement.id) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.red)
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .position(x: rect.midX, y: rect.midY)
        .gesture(bodyDrag)
        .overlay(resizeHandle, alignment: .bottomTrailing)
        .contextMenu {
            Button("Apply to every page") { appState.applyToEveryPage(id: placement.id) }
            Divider()
            Button(role: .destructive) {
                appState.removePlacement(id: placement.id)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - Content dispatch

    @ViewBuilder
    private var content: some View {
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
            dateText(text)
        case .freeText(let text, let fontSize):
            freeText(text, fontSize: fontSize)
        case .checkbox(let isChecked):
            Button {
                appState.updateContent(id: placement.id, content: .checkbox(isChecked: !isChecked))
            } label: {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
        }
    }

    private func dateText(_ text: String) -> some View {
        TextField("", text: Binding(
            get: { text },
            set: { appState.updateContent(id: placement.id, content: .date(text: $0)) }
        ))
        .textFieldStyle(.plain)
        .font(.system(size: max(10, pixelRect.height * 0.55)))
        .foregroundStyle(Color.black)
        .padding(.horizontal, 2)
        .background(Color.white.opacity(0.001))
    }

    private func freeText(_ text: String, fontSize: CGFloat) -> some View {
        TextField("Text", text: Binding(
            get: { text },
            set: { appState.updateContent(id: placement.id, content: .freeText(text: $0, fontSize: fontSize)) }
        ))
        .textFieldStyle(.plain)
        .font(.system(size: fontSize))
        .foregroundStyle(Color.black)
        .padding(.horizontal, 2)
        .background(Color.white.opacity(0.001))
    }

    // MARK: - Drag body

    private var bodyDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = pixelRect
                    appState.selectedPlacementID = placement.id
                }
                guard let start = dragStart else { return }
                let newOrigin = CGPoint(
                    x: start.origin.x + value.translation.width,
                    y: start.origin.y + value.translation.height
                )
                emit(origin: newOrigin, size: start.size)
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: - Resize handle

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right.square.fill")
            .font(.system(size: 14))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.accentColor)
            .padding(2)
            .contentShape(Rectangle())
            .offset(x: 6, y: 6)
            .gesture(resizeDrag)
    }

    private var resizeDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = pixelRect
                    appState.selectedPlacementID = placement.id
                }
                guard let start = dragStart else { return }
                let keepAspect = placement.content.isImageBacked
                let minSide: CGFloat = 24
                let proposedW = max(minSide, start.width + value.translation.width)
                let maxW = pageSize.width - start.origin.x
                var newW = min(proposedW, maxW)

                let newH: CGFloat
                if keepAspect, start.height > 0 {
                    let aspect = start.width / start.height
                    let heightCap = pageSize.height - start.origin.y
                    newH = min(newW / aspect, heightCap)
                    newW = newH * aspect
                } else {
                    let proposedH = max(minSide, start.height + value.translation.height)
                    let maxH = pageSize.height - start.origin.y
                    newH = min(proposedH, maxH)
                }
                emit(origin: start.origin, size: CGSize(width: newW, height: newH))
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: - Normalize + emit

    private func emit(origin: CGPoint, size: CGSize) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        let clampedX = min(max(origin.x, 0), max(0, pageSize.width - size.width))
        let clampedY = min(max(origin.y, 0), max(0, pageSize.height - size.height))
        let normalized = CGRect(
            x: clampedX / pageSize.width,
            y: clampedY / pageSize.height,
            width: size.width / pageSize.width,
            height: size.height / pageSize.height
        )
        appState.updatePlacement(id: placement.id, normalizedRect: normalized)
    }
}
