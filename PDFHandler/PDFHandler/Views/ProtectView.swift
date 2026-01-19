//
//  ProtectView.swift
//  PDFHandler
//
//  View for password protecting PDFs
//

import SwiftUI
import PDFKit

struct ProtectOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var confirmPassword = ""
    @State private var statusMessage = ""
    @State private var isSuccess = false
    @State private var showPasswords = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("$ ./protect")
                        .font(SumiTypography.monoLarge)
                        .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    Text("Add password protection to PDF")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(Color.stonegrey)
                }
                .padding(.bottom, 8)

                if appState.currentPDF == nil {
                    Text("No PDF selected. Open a file first.")
                        .font(SumiTypography.mono)
                        .foregroundStyle(Color.stonegrey)
                        .padding(.vertical, 20)
                } else {
                    // Current file info
                    if let url = appState.currentPDFURL, let pdf = appState.currentPDF {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("--input")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                            Text(url.lastPathComponent)
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)
                            Text("\(pdf.pageCount) pages")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Password options
                    VStack(alignment: .leading, spacing: 16) {
                        // Owner password (for full access)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("--owner-password")
                                    .font(SumiTypography.mono)
                                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                                Spacer()
                                Button(action: { showPasswords.toggle() }) {
                                    Text(showPasswords ? "[hide]" : "[show]")
                                        .font(SumiTypography.monoSmall)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.stonegrey)
                            }

                            Text("Full access password (for editing)")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)

                            Group {
                                if showPasswords {
                                    TextField("Owner password", text: $appState.ownerPassword)
                                } else {
                                    SecureField("Owner password", text: $appState.ownerPassword)
                                }
                            }
                            .font(SumiTypography.mono)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.stonegrey.opacity(0.1))
                            .cornerRadius(4)
                        }

                        // User password (to open document)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("--user-password")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                            Text("Password required to open (optional)")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)

                            Group {
                                if showPasswords {
                                    TextField("User password", text: $appState.userPassword)
                                } else {
                                    SecureField("User password", text: $appState.userPassword)
                                }
                            }
                            .font(SumiTypography.mono)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.stonegrey.opacity(0.1))
                            .cornerRadius(4)

                            if !appState.userPassword.isEmpty {
                                Group {
                                    if showPasswords {
                                        TextField("Confirm password", text: $confirmPassword)
                                    } else {
                                        SecureField("Confirm password", text: $confirmPassword)
                                    }
                                }
                                .font(SumiTypography.mono)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color.stonegrey.opacity(0.1))
                                .cornerRadius(4)

                                if !confirmPassword.isEmpty && confirmPassword != appState.userPassword {
                                    Text("⚠ Passwords do not match")
                                        .font(SumiTypography.monoSmall)
                                        .foregroundStyle(Color.red)
                                }
                            }
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Permissions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("--permissions")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        Toggle(isOn: $appState.allowPrinting) {
                            HStack {
                                Image(systemName: "printer")
                                Text("Allow printing")
                                    .font(SumiTypography.mono)
                            }
                        }
                        .toggleStyle(.checkbox)

                        Toggle(isOn: $appState.allowCopying) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("Allow copying text")
                                    .font(SumiTypography.mono)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Progress
                    if appState.isApplyingSecurity {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("encrypting...")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            ProgressView(value: appState.securityProgress)
                                .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            Text("\(Int(appState.securityProgress * 100))%")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)
                        }
                    }

                    // Status message
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(isSuccess ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen) : Color.red)
                    }

                    Spacer()

                    // Protect button
                    Button(action: performProtect) {
                        Text("[protect pdf]")
                            .font(SumiTypography.mono)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(
                        canProtect
                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            : Color.stonegrey.opacity(0.3)
                    )
                    .foregroundStyle(canProtect ? Color.inkBlack : Color.stonegrey)
                    .cornerRadius(4)
                    .disabled(!canProtect || appState.isApplyingSecurity)
                }
            }
            .padding(20)
        }
    }

    private var canProtect: Bool {
        guard appState.currentPDF != nil else { return false }
        guard !appState.ownerPassword.isEmpty else { return false }
        if !appState.userPassword.isEmpty && appState.userPassword != confirmPassword {
            return false
        }
        return true
    }

    private func performProtect() {
        guard let url = appState.currentPDFURL else { return }

        Task {
            appState.isApplyingSecurity = true
            appState.securityProgress = 0
            statusMessage = ""

            do {
                let options = SecurityOptions(
                    ownerPassword: appState.ownerPassword,
                    userPassword: appState.userPassword,
                    allowPrinting: appState.allowPrinting,
                    allowCopying: appState.allowCopying
                )

                let result = try await appState.pdfToolsService.applySecurity(
                    pdfURL: url,
                    options: options,
                    progressHandler: { progress in
                        Task { @MainActor in
                            appState.securityProgress = progress
                        }
                    }
                )
                statusMessage = "✓ protected → \(result.outputURL.lastPathComponent)"
                isSuccess = true

                // Clear passwords
                appState.ownerPassword = ""
                appState.userPassword = ""
                confirmPassword = ""
            } catch {
                statusMessage = "✗ error: \(error.localizedDescription)"
                isSuccess = false
            }

            appState.isApplyingSecurity = false
        }
    }
}
