//
//  PreferencesView.swift
//  PDFHandler
//
//  User preferences and settings
//

import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ConversionPreferencesView()
                .tabItem {
                    Label("Conversion", systemImage: "doc.text")
                }

            CompressionPreferencesView()
                .tabItem {
                    Label("Compression", systemImage: "arrow.down.right.and.arrow.up.left")
                }

            AdvancedPreferencesView()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @AppStorage("outputDirectory") private var outputDirectory: String = ""
    @AppStorage("openFinderAfterConversion") private var openFinderAfterConversion = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("keepWindowOnTop") private var keepWindowOnTop = false

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Output Directory", text: $outputDirectory)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        selectOutputDirectory()
                    }

                    Button("Reset") {
                        outputDirectory = ""
                    }
                    .disabled(outputDirectory.isEmpty)
                }

                Text("Leave empty to save next to source file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Output Location")
            }

            Section {
                Toggle("Open Finder after processing", isOn: $openFinderAfterConversion)
                Toggle("Show notifications", isOn: $showNotifications)
                Toggle("Keep window on top", isOn: $keepWindowOnTop)
            } header: {
                Text("Behavior")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url.path
        }
    }
}

// MARK: - Conversion Preferences

struct ConversionPreferencesView: View {
    @AppStorage("includeYAMLFrontmatter") private var includeYAMLFrontmatter = true
    @AppStorage("imageOutputFormat") private var imageOutputFormat = "png"
    @AppStorage("imageNamingConvention") private var imageNamingConvention = "sequential"
    @AppStorage("tableFallbackMode") private var tableFallbackMode = "code_block"
    @AppStorage("preserveLinks") private var preserveLinks = true
    @AppStorage("performOCR") private var performOCR = true
    @AppStorage("ocrLanguages") private var ocrLanguages = "en-US"

    var body: some View {
        Form {
            Section {
                Toggle("Include YAML frontmatter", isOn: $includeYAMLFrontmatter)
                Toggle("Preserve hyperlinks", isOn: $preserveLinks)
            } header: {
                Text("Markdown Output")
            }

            Section {
                Picker("Image format", selection: $imageOutputFormat) {
                    Text("PNG (Lossless)").tag("png")
                    Text("JPEG (Smaller)").tag("jpeg")
                }

                Picker("Naming convention", selection: $imageNamingConvention) {
                    Text("Sequential (image_001)").tag("sequential")
                    Text("Page-based (page1_img1)").tag("page_number")
                    Text("Descriptive (figure_1)").tag("descriptive")
                }
            } header: {
                Text("Image Extraction")
            }

            Section {
                Picker("Complex table handling", selection: $tableFallbackMode) {
                    Text("Code Block").tag("code_block")
                    Text("CSV Export").tag("csv")
                    Text("HTML Table").tag("html")
                }
            } header: {
                Text("Tables")
            }

            Section {
                Toggle("Enable OCR for scanned documents", isOn: $performOCR)

                if performOCR {
                    TextField("Languages (comma-separated)", text: $ocrLanguages)
                        .textFieldStyle(.roundedBorder)

                    Text("e.g., en-US, de-DE, fr-FR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("OCR")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Compression Preferences

struct CompressionPreferencesView: View {
    @AppStorage("defaultCompressionPreset") private var defaultPreset = "ebook"
    @AppStorage("defaultImageDPI") private var defaultDPI = 150
    @AppStorage("defaultColorCompression") private var colorCompression = "JPEG"
    @AppStorage("preserveMetadata") private var preserveMetadata = true

    @State private var ghostscriptVersion: String?

    var body: some View {
        Form {
            Section {
                if let version = ghostscriptVersion {
                    LabeledContent("Ghostscript Version", value: version)
                } else {
                    HStack {
                        Text("Ghostscript")
                        Spacer()
                        Text("Not installed")
                            .foregroundStyle(.orange)
                    }

                    Text("Install via: brew install ghostscript")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Ghostscript")
            }

            Section {
                Picker("Default preset", selection: $defaultPreset) {
                    Text("Prepress (Print-ready)").tag("prepress")
                    Text("Printer (High-quality)").tag("printer")
                    Text("eBook (Digital)").tag("ebook")
                    Text("Screen (Web/Email)").tag("screen")
                }

                HStack {
                    Text("Default DPI")
                    Slider(
                        value: Binding(
                            get: { Double(defaultDPI) },
                            set: { defaultDPI = Int($0) }
                        ),
                        in: 50...300,
                        step: 10
                    )
                    Text("\(defaultDPI)")
                        .frame(width: 40)
                }

                Picker("Color compression", selection: $colorCompression) {
                    Text("JPEG (Best compatibility)").tag("JPEG")
                    Text("JPEG2000 (Better quality)").tag("JPEG2000")
                    Text("Flate/ZIP (Lossless)").tag("Flate")
                }

                Toggle("Preserve metadata", isOn: $preserveMetadata)
            } header: {
                Text("Defaults")
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await checkGhostscript()
        }
    }

    private func checkGhostscript() async {
        let service = CompressionService()
        ghostscriptVersion = await service.getGhostscriptVersion()
    }
}

// MARK: - Advanced Preferences

struct AdvancedPreferencesView: View {
    @AppStorage("enableDebugLogging") private var enableDebugLogging = false
    @AppStorage("maxConcurrentOperations") private var maxConcurrent = 4
    @AppStorage("tempDirectory") private var tempDirectory = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Concurrent operations")
                    Stepper(value: $maxConcurrent, in: 1...8) {
                        Text("\(maxConcurrent)")
                    }
                }

                Toggle("Enable debug logging", isOn: $enableDebugLogging)
            } header: {
                Text("Performance")
            }

            Section {
                HStack {
                    TextField("Temporary directory", text: $tempDirectory)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        selectTempDirectory()
                    }

                    Button("Reset") {
                        tempDirectory = ""
                    }
                    .disabled(tempDirectory.isEmpty)
                }

                Text("Leave empty to use system temp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Storage")
            }

            Section {
                Button("Reset All Settings") {
                    resetAllSettings()
                }
                .foregroundStyle(.red)
            } header: {
                Text("Reset")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func selectTempDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            tempDirectory = url.path
        }
    }

    private func resetAllSettings() {
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
    }
}

#Preview {
    PreferencesView()
}
