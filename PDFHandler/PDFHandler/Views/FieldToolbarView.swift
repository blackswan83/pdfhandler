//
//  FieldToolbarView.swift
//  PDFHandler
//
//  DocuSign-style palette of placeable field types. Whichever is
//  selected is the tool the next click on the PDF page drops.
//

import SwiftUI

struct FieldToolbarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FieldTool.allCases) { tool in
                Button {
                    appState.activeTool = tool
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 16, weight: .medium))
                        Text(tool.displayName)
                            .font(.caption2)
                    }
                    .frame(minWidth: 70, minHeight: 44)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(appState.activeTool == tool
                                  ? Color.accentColor.opacity(0.18)
                                  : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(appState.activeTool == tool ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                    .foregroundStyle(appState.activeTool == tool ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled(tool))
                .help(helpText(for: tool))
            }
            Spacer()
            hint
        }
    }

    // MARK: - Right-side hint text

    @ViewBuilder
    private var hint: some View {
        switch appState.activeTool {
        case .signature:
            needsAssetText("Pick a Signature in the sidebar, then click the page to place it.",
                           hasAsset: appState.activeSignatureID != nil)
        case .initials:
            needsAssetText("Pick an Initials asset in the sidebar, then click the page.",
                           hasAsset: appState.activeInitialsID != nil)
        case .date, .freeText, .checkbox:
            Text("Click the page to place a \(appState.activeTool.displayName.lowercased()).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func needsAssetText(_ text: String, hasAsset: Bool) -> some View {
        Text(hasAsset ? text.replacingOccurrences(of: "Pick ", with: "Click the page to place. Or pick ") : text)
            .font(.caption)
            .foregroundStyle(hasAsset ? .secondary : Color.orange)
    }

    private func isDisabled(_ tool: FieldTool) -> Bool {
        switch tool {
        case .signature: return appState.activeSignatureID == nil
        case .initials:  return appState.activeInitialsID  == nil
        default: return false
        }
    }

    private func helpText(for tool: FieldTool) -> String {
        switch tool {
        case .signature: return "Place your signature"
        case .initials:  return "Place initials"
        case .date:      return "Place today's date"
        case .freeText:  return "Place a free-text field"
        case .checkbox:  return "Place a checkbox"
        }
    }
}
