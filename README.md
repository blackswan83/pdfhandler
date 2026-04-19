# PDF Handler

A native macOS application for converting PDF documents to Markdown and compressing PDFs with precise size targeting.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### PDF to Markdown Conversion
- **Text extraction** with intelligent structure detection (headings, paragraphs, lists)
- **Table handling** with Markdown table syntax and fallback options (code blocks, CSV, HTML)
- **Image extraction** to companion folders with PNG/JPEG output
- **OCR support** using macOS Vision framework for scanned documents
- **Hyperlink preservation** as inline Markdown links
- **YAML frontmatter** generation with document metadata

### PDF Compression
- **Ghostscript backend** for industry-standard compression quality
- **Target size slider** for precise compression control
- **Live preview** of estimated output size
- **Multiple presets**: Prepress, Printer, eBook, Screen
- **Advanced options**: DPI control, color compression, font subsetting, grayscale conversion

### Batch Processing
- Process multiple PDFs simultaneously
- Consistent output settings across all files
- Progress tracking per file

### Platform Integration
- Native SwiftUI interface with dark mode support
- Drag-and-drop file handling
- Menu bar utility for quick conversions
- macOS Services integration (right-click context menu)
- Keyboard shortcuts

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0+ (for development)
- [Ghostscript](https://www.ghostscript.com/) (for PDF compression)

### Installing Ghostscript

```bash
brew install ghostscript
```

## Installation

### From Source

1. Clone the repository:
```bash
git clone https://github.com/yourusername/pdfhandler.git
cd pdfhandler
```

2. Open the Swift package in Xcode (the `.xcodeproj` is stale — don't use it):
```bash
xed PDFHandler/Package.swift
```

3. Build and run (⌘R), or use SwiftUI Previews on any `View` for a sub-2s UI loop.

### Fast iteration from the terminal

```bash
./scripts/dev.sh          # debug build → launch a real .app bundle
./scripts/dev.sh --watch  # rebuild + relaunch on any .swift change (needs fswatch)
```

`dev.sh` wraps the SwiftPM debug output in `build/PDF Handler (Debug).app` so
`MenuBarExtra`, dock icon, document types, and services all behave correctly —
`swift run` on the bare executable does not.

### Release build

```bash
./scripts/package.sh      # produces build/PDF Handler.app and build/PDFHandler.dmg
./scripts/package.sh --app-only
```

## Usage

### Converting PDFs to Markdown

1. Launch PDF Handler
2. Drag and drop a PDF onto the app window, or click "Select PDFs"
3. Configure conversion options:
   - Toggle YAML frontmatter
   - Choose image format (PNG/JPEG)
   - Enable/disable OCR for scanned documents
4. Click "Convert to Markdown"
5. The output file is saved alongside the source PDF

### Compressing PDFs

1. Select the "Compress PDF" tab
2. Adjust the target size slider:
   - **90-100%**: Prepress (print-ready, archival)
   - **60-90%**: Printer (high-quality printing)
   - **30-60%**: eBook (digital distribution)
   - **10-30%**: Screen (web/email sharing)
3. Click "Compress PDF"
4. View the compression results with before/after comparison

### Menu Bar Quick Actions

Click the menu bar icon for:
- Quick PDF drop zone
- One-click conversion
- One-click compression
- Recent files access

## Project Structure

```
PDFHandler/
├── PDFHandler.xcodeproj/     # Xcode project
├── Package.swift             # Swift Package Manager config
└── PDFHandler/
    ├── App/
    │   ├── PDFHandlerApp.swift    # App entry point
    │   └── AppState.swift         # Global state management
    ├── Views/
    │   ├── ContentView.swift           # Main view
    │   ├── ConversionOptionsView.swift # Markdown options
    │   ├── CompressionOptionsView.swift # Compression options
    │   ├── BatchProcessingView.swift   # Batch mode
    │   ├── PreferencesView.swift       # Settings
    │   └── MenuBarView.swift           # Menu bar extra
    ├── Models/
    │   ├── ConversionModels.swift      # Conversion data types
    │   └── CompressionModels.swift     # Compression data types
    ├── Services/
    │   ├── PDFService.swift            # PDF parsing
    │   ├── MarkdownConverter.swift     # Markdown generation
    │   ├── OCRService.swift            # Vision OCR
    │   └── CompressionService.swift    # Ghostscript wrapper
    ├── Utilities/
    │   └── ServiceProvider.swift       # macOS Services
    └── Resources/
        ├── Info.plist
        └── PDFHandler.entitlements
```

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open PDF | ⌘O |
| Convert to Markdown | ⇧⌘M |
| Compress PDF | ⇧⌘K |
| Toggle Sidebar | ⌃⌘S |
| Preferences | ⌘, |

## Configuration

Preferences are accessible via **PDF Handler → Settings** (⌘,):

- **General**: Output directory, notifications, behavior
- **Conversion**: Frontmatter, images, tables, OCR languages
- **Compression**: Default preset, DPI, color compression
- **Advanced**: Concurrent operations, debug logging

## API Reference

### MarkdownConverter

```swift
let converter = MarkdownConverter()
let result = try await converter.convert(
    pdf: pdfDocument,
    sourceURL: fileURL,
    options: ConversionOptions(
        includeYAMLFrontmatter: true,
        imageOutputFormat: .png,
        performOCR: true
    ),
    progressHandler: { progress in
        print("Progress: \(progress * 100)%")
    }
)
```

### CompressionService

```swift
let service = CompressionService()
let result = try await service.compress(
    pdfURL: fileURL,
    targetRatio: 0.5, // 50% of original size
    progressHandler: { progress in
        print("Progress: \(progress * 100)%")
    }
)
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Ghostscript](https://www.ghostscript.com/) for PDF compression
- [PDFKit](https://developer.apple.com/documentation/pdfkit) for PDF handling
- [Vision](https://developer.apple.com/documentation/vision) for OCR capabilities
