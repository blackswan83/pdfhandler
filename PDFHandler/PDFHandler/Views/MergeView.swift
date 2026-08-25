//
//  MergeView.swift
//  PDFHandler
//
//  Merge-mode detail pane. Add PDFs (button or drag), reorder them
//  by dragging rows in the List, set an output name, Merge.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MergeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack {
                Button {
                    pickPDFs()
                } label: {
                    Label("Add PDFs…", systemImage: "plus")
                }
                if !appState.mergeItems.isEmpty {
                    Button(role: .destructive) {
                        appState.mergeItems.removeAll()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                HStack {
                    Text("Output name:")
                    TextField("merged", text: $appState.mergeOutputName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            }

            list

            HStack {
                Button {
                    appState.runMerge()
                } label: {
                    if appState.mergeIsRunning {
                        Label("Merging…", systemImage: "gearshape")
                    } else {
                        Label("Merge", systemImage: "doc.on.doc.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.mergeItems.count < 2 || appState.mergeIsRunning)

                if appState.mergeIsRunning {
                    ProgressView(value: appState.mergeProgress).frame(maxWidth: 220)
                }
                Spacer()
            }

            if let output = appState.mergeResultURL {
                resultCard(output)
            }
            if let error = appState.mergeError {
                errorBanner(error)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Merge PDFs", systemImage: "doc.on.doc").font(.title2.bold())
            Text("Add two or more PDFs, drag the rows to reorder, and merge. Output saves next to the first source as \"<name>.pdf\".")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if appState.mergeItems.isEmpty {
            dropPlaceholder
        } else {
            List {
                ForEach(appState.mergeItems) { item in
                    row(item)
                }
                .onMove { indices, newOffset in
                    appState.mergeItems.move(fromOffsets: indices, toOffset: newOffset)
                }
                .onDelete { indexSet in
                    appState.mergeItems.remove(atOffsets: indexSet)
                }
            }
            .frame(minHeight: 200, idealHeight: 280)
            .listStyle(.bordered)
            .onDrop(of: PDFDrop.acceptedTypes, isTargeted: nil) { providers in
                PDFDrop.receive(providers) { urls in
                    appState.mergeItems.append(contentsOf: urls.map { MergeItem(url: $0) })
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: MergeItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).font(.body)
                Text(item.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(role: .destructive) {
                appState.mergeItems.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private var dropPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop PDFs here, or click Add PDFs…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
        )
        .onDrop(of: PDFDrop.acceptedTypes, isTargeted: nil) { providers in
            PDFDrop.receive(providers) { urls in
                appState.mergeItems.append(contentsOf: urls.map { MergeItem(url: $0) })
            }
        }
    }

    // MARK: - Result + errors

    private func resultCard(_ url: URL) -> some View {
        HStack {
            Label("Merged: \(url.lastPathComponent)", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color.green)
            Spacer()
        }
        .padding(12)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
            Text(message).font(.callout)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func pickPDFs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            appState.mergeItems.append(contentsOf: panel.urls.map { MergeItem(url: $0) })
        }
    }
}
