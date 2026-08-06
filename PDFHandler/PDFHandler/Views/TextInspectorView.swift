//
//  TextInspectorView.swift
//  PDFHandler
//
//  Typography controls for text fields. Edits the selected field when
//  there is one, otherwise sets what the next field will use — so it
//  works both as an inspector and as a set of defaults.
//

import SwiftUI

struct TextInspectorView: View {
    @EnvironmentObject var appState: AppState

    private var style: TextStyle { appState.inspectorTextStyle }
    private var editingSelection: Bool { appState.selectedTextPlacement != nil }

    /// One control changes one field; the rest of the style carries
    /// through unchanged.
    private func binding<T>(_ keyPath: WritableKeyPath<TextStyle, T>) -> Binding<T> {
        Binding(
            get: { style[keyPath: keyPath] },
            set: { newValue in
                var updated = style
                updated[keyPath: keyPath] = newValue
                appState.applyTextStyle(updated)
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat")
                .foregroundStyle(.secondary)

            Picker("", selection: binding(\.font)) {
                ForEach(TextFont.allCases) { font in
                    Text(font.displayName).tag(font)
                }
            }
            .labelsHidden()
            .frame(width: 116)
            .help("Typeface")

            Divider().frame(height: 16)

            Toggle("Fit to box", isOn: binding(\.autoFit))
                .toggleStyle(.checkbox)
                .help("Scale the text with the box instead of using a fixed size")

            HStack(spacing: 4) {
                Text("Size")
                Stepper(
                    value: binding(\.size),
                    in: TextStyle.minSize...TextStyle.maxSize,
                    step: 1
                ) {
                    Text("\(Int(style.size)) pt")
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 44, alignment: .leading)
                }
            }
            .disabled(style.autoFit)
            .foregroundStyle(style.autoFit ? .tertiary : .primary)
            .help(style.autoFit
                  ? "Turn off \"Fit to box\" to set an exact size"
                  : "Point size in the PDF, independent of zoom")

            Spacer()

            Text(editingSelection ? "Editing selected field" : "Applies to the next field")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}
