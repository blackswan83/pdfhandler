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
    @State private var pendingDelete: SavedSignature?
    @State private var confirmErase = false

    var body: some View {
        Section("Signatures") {
            rows(for: .signature, activeID: appState.activeSignatureID) { id in
                // Picking an asset also arms the matching tool so the
                // next page click places what the user just chose.
                appState.activeSignatureID = id
                appState.activeTool = .signature
            }
            addRow(label: "Add signature…") {
                appState.newSignatureRole = .signature
                appState.isPresentingNewSignature = true
            }
        }
        Section("Initials") {
            rows(for: .initials, activeID: appState.activeInitialsID) { id in
                appState.activeInitialsID = id
                appState.activeTool = .initials
            }
            addRow(label: "Add initials…") {
                appState.newSignatureRole = .initials
                appState.isPresentingNewSignature = true
            }
            storageRow
        }
        .confirmationDialog(
            "Delete \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                appState.deleteSignature(id: entry.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("Any fields using \"\(entry.name)\" on the open document will be removed. This cannot be undone.")
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
                    onDelete: { pendingDelete = entry }
                )
            }
        }
    }

    /// The library lives in Application Support, outside the app
    /// bundle, so it survives deleting and reinstalling the app.
    /// Surfacing that here — rather than leaving people to wonder why
    /// old signatures reappear — plus a way to clear it.
    @ViewBuilder
    private var storageRow: some View {
        Menu {
            Button("Reveal library in Finder…") { appState.revealSignatureLibrary() }
            Divider()
            Button("Erase all signatures…", role: .destructive) { confirmErase = true }
        } label: {
            Label("Library storage", systemImage: "externaldrive")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .help(appState.signatureLibraryURL.path)
        .confirmationDialog(
            "Erase every saved signature and initials entry?",
            isPresented: $confirmErase
        ) {
            Button("Erase", role: .destructive) { appState.eraseSignatureLibrary() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes them from \(appState.signatureLibraryURL.path) and removes any fields using them. It cannot be undone.")
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
