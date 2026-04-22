# PDF Handler

A native macOS application for working with PDFs — convert to Markdown, compress, merge, split, rotate, sign, watermark, and password‑protect.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Download

Grab the latest `PDFHandler-<version>.dmg` from either:

- **GitHub Releases** (attached automatically when a `v*` tag is pushed)
- **Actions → Build DMG → latest successful run → Artifacts** (built on every push)

Then open the DMG and drag **PDFHandler.app** into **Applications**. The first time you launch it, right‑click the app and choose *Open* to bypass Gatekeeper (the build is ad‑hoc signed — no Apple Developer ID needed).

## Features

### Tabs / screens
- **Quick Sign** — Type a name, pick a handwriting style, drag to position, apply to first or last page.
- **Convert** — PDF → Markdown with images, YAML frontmatter, hyperlinks, and optional OCR.
- **Compress** — Ghostscript‑backed compression with target‑size slider and 4 presets.
- **Merge** — Combine multiple PDFs into one, optionally adding bookmarks per source file.
- **Split** — All pages, page ranges, every N pages, or by max file size.
- **Rotate** — 90° / 180° / 270° on all or specific pages.
- **Sign** — Draw freehand or import an image signature; 9 preset positions or custom XY.
- **Protect** — Owner + user passwords; toggle printing / copying / modification / annotation.
- **Watermark** — Text or image; opacity, rotation, color, font, position, per‑page.
- **Batch** — Queue multiple PDFs and convert or compress them sequentially.
- **Menu‑bar quick actions** — Drop a PDF on the menu‑bar icon to convert or compress instantly.

### PDF → Markdown
- Text extraction with heading / paragraph / list detection
- Tables as Markdown (fallback to fenced code, CSV, or HTML)
- Image extraction to a companion `<name>_images/` folder (PNG or JPEG)
- Hyperlink preservation as inline Markdown links
- OCR via the macOS Vision framework (configurable languages; confidence shown)
- Optional YAML frontmatter with document metadata

### Compression
- Presets: **Prepress** (90–100%), **Printer** (60–90%), **eBook** (30–60%), **Screen** (10–30%)
- Manual target‑size slider (10–100% of original)
- DPI control (50–300), grayscale toggle, metadata preservation
- Uses the system `gs` (Ghostscript). Install with `brew install ghostscript`.

### Keyboard shortcuts
| Action | Shortcut |
|---|---|
| Open PDF | ⌘O |
| Convert to Markdown | ⇧⌘M |
| Compress PDF | ⇧⌘K |
| Toggle Sidebar | ⌃⌘S |
| Preferences | ⌘, |

## Requirements

- macOS 13.0 (Ventura) or later
- [Ghostscript](https://www.ghostscript.com/) — only needed for the Compress tab (`brew install ghostscript`)

## Build from source (terminal only, no Xcode IDE)

The app is built with Swift Package Manager and packaged with `hdiutil`. You only need the Xcode **Command Line Tools** — not the full Xcode app.

```bash
# one‑time: install the Command Line Tools if you don't already have them
xcode-select --install

git clone https://github.com/blackswan83/pdfhandler.git
cd pdfhandler

./scripts/build-dmg.sh
# → build/PDFHandler-<version>.dmg
# → build/PDFHandler.app
```

What the script does:
1. `swift build -c release` to compile the executable.
2. Assembles a proper `.app` bundle: `Contents/MacOS/PDFHandler`, `Contents/Info.plist`, `Contents/Resources/…`, `Contents/PkgInfo`.
3. Compiles the asset catalog with `actool` if real icons are present (the included asset catalog is empty by default — drop a 1024×1024 PNG and run `PDFHandler/PDFHandler/Resources/Assets.xcassets/AppIcon.appiconset/generate_icons.sh <source.png>` to generate all sizes).
4. Ad‑hoc codesigns the bundle and attaches the app entitlements.
5. Stages `PDFHandler.app` next to an `Applications` symlink and produces a compressed UDZO DMG with `hdiutil`.

If you just want the binary without a DMG:

```bash
cd PDFHandler
swift build -c release
# executable: .build/release/PDFHandler
```

## Continuous builds (GitHub Actions)

`.github/workflows/build-dmg.yml` runs `./scripts/build-dmg.sh` on a `macos-14` runner for every push and PR. Artifacts are uploaded under the workflow run (downloadable from the **Actions** tab). Pushing a `v*` tag additionally attaches the DMG to a GitHub Release.

```bash
git tag v1.0.0
git push origin v1.0.0
# Release with PDFHandler-1.0.0.dmg appears on GitHub in a few minutes
```

## Project structure

```
.
├── scripts/
│   └── build-dmg.sh              # swift build → .app → .dmg
├── .github/workflows/
│   └── build-dmg.yml             # CI build on macos-14
└── PDFHandler/
    ├── Package.swift             # SwiftPM manifest (executable + tests)
    ├── PDFHandler.xcodeproj/     # (optional) Xcode project, not required to build
    ├── PDFHandler/
    │   ├── App/                  # PDFHandlerApp, AppDelegate, AppState
    │   ├── Views/                # ContentView + one view per feature tab
    │   ├── Models/               # Conversion, Compression, PDFTools options
    │   ├── Services/             # PDF/Markdown/OCR/Compression/PDFTools
    │   ├── Utilities/            # ServiceProvider, DesignSystem
    │   └── Resources/
    │       ├── Info.plist        # copied into .app as Contents/Info.plist
    │       ├── PDFHandler.entitlements
    │       └── Assets.xcassets/AppIcon.appiconset/
    └── PDFHandlerTests/
        └── PDFHandlerTests.swift
```

## Platform integration

- **Finder services**: right‑click a PDF → *Services* → *PDF Handler / Convert to Markdown* or *Compress PDF* (registered via `NSServices` in `Info.plist`).
- **Document types**: PDF Handler advertises itself as an alternate handler for `com.adobe.pdf`.
- **Menu bar**: `MenuBarExtra` provides a drop zone and one‑click convert / compress / recents.

## Notes on signing & sandboxing

- The bundle is **ad‑hoc codesigned** (`codesign --sign -`). Good enough to run locally; users will see the Gatekeeper first‑run prompt.
- The App Sandbox is **disabled** in `PDFHandler.entitlements` because the Compress feature shells out to the `gs` binary. If you enable the sandbox, compression will stop working unless you ship Ghostscript in the bundle.
- For distribution outside your own machine, sign with a Developer ID and notarize — that's out of scope of this repo's CI.

## License

MIT — see [LICENSE](LICENSE).
