//
//  LibrarySidebarView.swift
//  PDFHandler
//
//  Sidebar that lists the saved signatures. Tapping one makes it the
//  "active" signature — the next click on the PDF preview drops it
//  onto the page. Includes an "Add new" button and per-row delete.
//

import SwiftUI
import AppKit

struct LibrarySidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if appState.signatures.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(appState.signatures) { entry in
                            row(for: entry)
                        }
                    }
                    .padding(8)
                }
            }

            Spacer(minLength: 0)

            Divider()
            footerHint
        }
        .frame(minWidth: 220, idealWidth: 240)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Signatures")
                .font(.headline)
            Spacer()
            Button {
                appState.isPresentingNewSignature = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Add a new signature")
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for entry: SavedSignature) -> some View {
        let isActive = appState.activeSignatureID == entry.id

        HStack(spacing: 10) {
            Button {
                appState.activeSignatureID = entry.id
            } label: {
                HStack(spacing: 10) {
                    if let image = entry.image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 28)
                            .padding(3)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                    Spacer(minLength: 0)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                appState.deleteSignature(id: entry.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .help("Delete")
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "signature")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("No signatures yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Add signature") {
                appState.isPresentingNewSignature = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Footer hint

    private var footerHint: some View {
        Text(appState.activeSignatureID == nil
             ? "Select a signature, then click on the page to place it."
             : "Click the page to place the selected signature. Drag to move, drag the handle to resize.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
    }
}
