//
//  SignView.swift
//  PDFHandler
//
//  Unified signing experience: capture once (draw/type/image),
//  persist as Identity (signature + initials), place on the page, sign.
//

import SwiftUI
import PDFKit
import AppKit

struct SignView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        SignViewContent(identityStore: appState.identityStore)
            .environmentObject(appState)
    }
}

private struct SignViewContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var identityStore: SignatureIdentityStore
    @Environment(\.colorScheme) var colorScheme

    @State private var workingAsset: SignatureAsset?
    @State private var activeSlot: SignatureIdentity.Slot = .signature
    @State private var placement: SignaturePlacement?
    @State private var pageIndex: Int = 0
    @State private var applyToAllPages: Bool = false
    @State private var statusMessage: String = ""
    @State private var isSuccess: Bool = false
    @State private var isCapturing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if appState.currentPDF == nil {
                emptyState
            } else {
                identityBar
                Divider().background(Color.stonegrey.opacity(0.3))

                if isCapturing || effectiveAsset == nil {
                    capturePane
                } else {
                    placementPane
                }
            }
        }
        .padding(20)
        .onChange(of: appState.currentPDFURL) { _ in
            pageIndex = 0
            placement = nil
            statusMessage = ""
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("$ ./sign")
                .font(SumiTypography.monoLarge)
                .foregroundStyle(accent)
            Text("Capture once · drag to place · sign.")
                .font(SumiTypography.monoSmall)
                .foregroundStyle(Color.stonegrey)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(Color.stonegrey)
            Text("open a PDF to sign")
                .font(SumiTypography.mono)
                .foregroundStyle(Color.stonegrey)
            Button(action: { appState.showFilePicker = true }) {
                Text("[choose file]")
                    .font(SumiTypography.mono)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(accent)
                    .foregroundStyle(Color.inkBlack)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Identity bar

    private var identityBar: some View {
        let identity = appState.identityStore.identity
        return HStack(alignment: .top, spacing: 12) {
            slotChip(
                label: "Signature",
                asset: identity.signature,
                isActive: activeSlot == .signature && !isCapturing,
                tall: true,
                onTap: { useSlot(.signature) },
                onReplace: { startCapture(for: .signature) },
                onClear: { appState.identityStore.clear(.signature) }
            )
            slotChip(
                label: "Initials",
                asset: identity.initials,
                isActive: activeSlot == .initials && !isCapturing,
                tall: false,
                onTap: { useSlot(.initials) },
                onReplace: { startCapture(for: .initials) },
                onClear: { appState.identityStore.clear(.initials) }
            )
            Spacer()
        }
    }

    @ViewBuilder
    private func slotChip(
        label: String,
        asset: SignatureAsset?,
        isActive: Bool,
        tall: Bool,
        onTap: @escaping () -> Void,
        onReplace: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(SumiTypography.monoSmall)
                .foregroundStyle(Color.stonegrey)

            if let asset = asset, let img = asset.image {
                Button(action: onTap) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: tall ? 180 : 90, height: 48)
                        .padding(8)
                        .background(Color.white)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isActive ? accent : Color.mist, lineWidth: isActive ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Button(action: onReplace) {
                        Text("[replace]").font(SumiTypography.monoSmall)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.stonegrey)

                    Button(action: onClear) {
                        Text("[×]").font(SumiTypography.monoSmall)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.red.opacity(0.8))
                }
            } else {
                Button(action: onReplace) {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 14))
                        Text("add \(label.lowercased())")
                            .font(SumiTypography.monoSmall)
                    }
                    .frame(width: tall ? 180 : 90, height: 48)
                    .padding(8)
                    .foregroundStyle(Color.stonegrey)
                    .background(Color.stonegrey.opacity(0.06))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.mist, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Capture pane

    private var capturePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("new \(activeSlot == .initials ? "initials" : "signature")")
                    .font(SumiTypography.mono)
                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                Spacer()

                if effectiveAsset != nil {
                    Button(action: { isCapturing = false }) {
                        Text("[cancel]").font(SumiTypography.monoSmall)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.stonegrey)
                }
            }

            SignatureCaptureView { asset in
                appState.identityStore.set(asset, for: activeSlot)
                workingAsset = asset
                isCapturing = false
            }
        }
    }

    // MARK: Placement pane

    @ViewBuilder
    private var placementPane: some View {
        if let asset = effectiveAsset, let image = asset.image, let pdf = appState.currentPDF {
            VStack(spacing: 12) {
                SignaturePlacementView(
                    document: pdf,
                    signatureImage: image,
                    pageIndex: $pageIndex,
                    onPlacementChange: { placement = $0 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colorScheme == .dark ? Color.sumiGrey.opacity(0.3) : Color.white.opacity(0.6))
                .cornerRadius(6)

                actionBar
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                Toggle(isOn: $applyToAllPages) {
                    Text("Apply to all pages")
                        .font(SumiTypography.monoSmall)
                }
                .toggleStyle(.checkbox)

                Spacer()

                if appState.isSigning {
                    ProgressView(value: appState.signatureProgress)
                        .progressViewStyle(.linear)
                        .tint(accent)
                        .frame(width: 120)
                }

                Button(action: signDocument) {
                    Text(appState.isSigning ? "[signing…]" : "[sign document]")
                        .font(SumiTypography.mono)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(accent)
                        .foregroundStyle(Color.inkBlack)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(appState.isSigning || effectiveAsset == nil || placement == nil)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(isSuccess ? accent : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Logic

    private var effectiveAsset: SignatureAsset? {
        if isCapturing { return workingAsset }
        switch activeSlot {
        case .signature: return appState.identityStore.identity.signature ?? workingAsset
        case .initials:  return appState.identityStore.identity.initials  ?? workingAsset
        }
    }

    private func useSlot(_ slot: SignatureIdentity.Slot) {
        activeSlot = slot
        isCapturing = false
        workingAsset = nil
    }

    private func startCapture(for slot: SignatureIdentity.Slot) {
        activeSlot = slot
        workingAsset = nil
        isCapturing = true
    }

    private func signDocument() {
        guard let url = appState.currentPDFURL,
              let asset = effectiveAsset,
              let image = asset.image,
              let placement = placement else { return }

        Task {
            appState.isSigning = true
            appState.signatureProgress = 0
            statusMessage = ""

            do {
                let options = SignatureOptions(
                    signatureImage: image,
                    position: .custom,
                    customX: placement.pdfRect.origin.x,
                    customY: placement.pdfRect.origin.y,
                    width: placement.pdfRect.width,
                    height: placement.pdfRect.height,
                    page: placement.page,
                    applyToAllPages: applyToAllPages
                )

                let result = try await appState.pdfToolsService.addSignature(
                    pdfURL: url,
                    options: options,
                    progressHandler: { progress in
                        Task { @MainActor in
                            appState.signatureProgress = progress
                        }
                    }
                )
                statusMessage = "✓ signed \(result.pagesModified) page(s) → \(result.outputURL.lastPathComponent)"
                isSuccess = true
                NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
            } catch {
                statusMessage = "✗ \(error.localizedDescription)"
                isSuccess = false
            }

            appState.isSigning = false
        }
    }

    private var accent: Color {
        colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen
    }
}

#Preview {
    SignView()
        .environmentObject(AppState())
        .frame(width: 900, height: 700)
}
