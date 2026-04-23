//
//  LibrarySidebarView.swift
//  PDFHandler
//
//  Two sub-lists of library entries (Signatures + Initials) that
//  appear inside the main sidebar when the user is in Sign mode.
//  Each row: thumbnail + name; tap to activate that entry as the
//  active asset for the corresponding field tool; trash to delete.
//

import SwiftUI
import AppKit

/// Renders as two `Section`s intended to live inside the sidebar's
/// outer `List`.
struct LibrarySidebarSections: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Section("Signatures") {
            rows(for: .signature, activeID: appState.activeSignatureID) { id in
                appState.activeSignatureID = id
            }
            addRow(label: "Add signature…") {
                appState.newSignatureRole = .signature
                appState.isPresentingNewSignature = true
            }
        }
        Section("Initials") {
            rows(for: .initials, activeID: appState.activeInitialsID) { id in
                appState.activeInitialsID = id
            }
            addRow(label: "Add initials…") {
                appState.newSignatureRole = .initials
                appState.isPresentingNewSignature = true
            }
        }
    }

    @ViewBuilder
    private func rows(
        for role: SavedSignatureRole,
        activeID: UUID?,
        onActivate: @escaping (UUID) -> Void
    ) -> some View {
        let entries = appState.signatures(role: role)
        if entries.isEmpty {
            Text(role == .signature
                 ? "No signatures yet."
                 : "No initials yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(entries) { entry in
                LibraryRow(
                    entry: entry,
                    isActive: entry.id == activeID,
                    onActivate: { onActivate(entry.id) },
                    onDelete: { appState.deleteSignature(id: entry.id) }
                )
            }
        }
    }

    private func addRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: "plus.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryRow: View {
    let entry: SavedSignature
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onActivate) {
                HStack(spacing: 8) {
                    if let image = entry.image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 22)
                            .padding(2)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
    }
}
