//
//  SignaturePlacementView.swift
//  PDFHandler
//
//  A single signature overlaid on the PDF preview. Supports:
//    • drag the body to reposition
//    • drag the bottom-right handle to resize (keeps aspect ratio)
//    • a delete button in the top-right corner
//  Position and size are expressed in pixels inside the given
//  `pageSize` box; the parent maps those back to normalized coords.
//

import SwiftUI
import AppKit

struct SignaturePlacementView: View {
    let placement: SignaturePlacement
    let signature: SavedSignature
    let pageSize: CGSize
    var onUpdate: (CGRect) -> Void   // new normalized rect
    var onDelete: () -> Void

    @State private var dragStart: CGRect?

    private var pixelRect: CGRect {
        CGRect(
            x: placement.normalizedRect.origin.x * pageSize.width,
            y: placement.normalizedRect.origin.y * pageSize.height,
            width: placement.normalizedRect.width * pageSize.width,
            height: placement.normalizedRect.height * pageSize.height
        )
    }

    var body: some View {
        let rect = pixelRect

        ZStack(alignment: .topTrailing) {
            if let image = signature.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: rect.width, height: rect.height)
                    .background(Color.white.opacity(0.001)) // hit-test entire bounds
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.accentColor.opacity(0.9), lineWidth: 1)
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: rect.width, height: rect.height)
            }

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.red)
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .position(x: rect.midX, y: rect.midY)
        .gesture(bodyDrag)
        .overlay(resizeHandle, alignment: .bottomTrailing)
    }

    // MARK: - Body drag (reposition)

    private var bodyDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil { dragStart = pixelRect }
                guard let start = dragStart else { return }
                let newOrigin = CGPoint(
                    x: start.origin.x + value.translation.width,
                    y: start.origin.y + value.translation.height
                )
                emit(origin: newOrigin, size: start.size)
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: - Resize handle (bottom-right, keeps aspect ratio)

    private var resizeHandle: some View {
        // Positioned so the bulk of the handle sits inside the signature bounds.
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
                if dragStart == nil { dragStart = pixelRect }
                guard let start = dragStart else { return }
                let aspect = start.height == 0 ? 1 : start.width / start.height
                let proposedWidth = max(40, start.width + value.translation.width)
                let newWidth = min(proposedWidth, pageSize.width - start.origin.x)
                let newHeight = min(newWidth / aspect, pageSize.height - start.origin.y)
                let finalWidth = newHeight * aspect
                emit(origin: start.origin,
                     size: CGSize(width: finalWidth, height: newHeight))
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: - Normalization

    private func emit(origin: CGPoint, size: CGSize) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        let clampedX = min(max(origin.x, 0), pageSize.width - size.width)
        let clampedY = min(max(origin.y, 0), pageSize.height - size.height)
        let normalized = CGRect(
            x: clampedX / pageSize.width,
            y: clampedY / pageSize.height,
            width: size.width / pageSize.width,
            height: size.height / pageSize.height
        )
        onUpdate(normalized)
    }
}
