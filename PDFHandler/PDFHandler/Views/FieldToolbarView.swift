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
                    // Picking the signature / initials tool with an
                    // empty library opens the creation sheet instead
                    // of dead-ending on a disabled button.
                    switch tool {
                    case .signature where appState.activeSignatureID == nil:
                        appState.newSignatureRole = .signature
                        appState.isPresentingNewSignature = true
                    case .initials where appState.activeInitialsID == nil:
                        appState.newSignatureRole = .initials
                        appState.isPresentingNewSignature = true
                    default:
                        break
                    }
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
            needsAssetText("Click the page to place your signature. Drag to move, corner knob to resize.",
                           missing: "No signature yet — click the page to create one.",
                           hasAsset: appState.activeSignatureID != nil)
        case .initials:
            needsAssetText("Click the page to place your initials.",
                           missing: "No initials yet — click the page to create them.",
                           hasAsset: appState.activeInitialsID != nil)
        case .date, .freeText:
            Text("Click the page to place. Double-click the field to edit its text; ⌫ deletes, arrows nudge.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .checkbox:
            Text("Click the page to place a checkbox; click it to toggle.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func needsAssetText(_ text: String, missing: String, hasAsset: Bool) -> some View {
        Text(hasAsset ? text : missing)
            .font(.caption)
            .foregroundStyle(hasAsset ? Color.secondary : Color.orange)
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
