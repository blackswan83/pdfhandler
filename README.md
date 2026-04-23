# PDF Handler

A focused macOS app for **signing PDFs**. Keep a library of signatures (typed, drawn, imported, pasted), drop one onto a page, drag to reposition, and drag the corner handle to resize — just like DocuSign, but local and free.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Download

Grab `PDFHandler-<version>.dmg` from either:

- **GitHub Releases** (attached automatically when a `v*` tag is pushed)
- **Actions → Build DMG → latest successful run → Artifacts** (built on every push)

Drag **PDFHandler.app** into **Applications**. Because the build is ad-hoc signed (no Apple Developer ID), macOS will block the first launch. Unblock it with:

```bash
xattr -d com.apple.quarantine /Applications/PDFHandler.app
```

Then double-click to launch. (On macOS 13 Ventura you can right-click → Open instead; on Sonoma / Sequoia use **System Settings → Privacy & Security → Open Anyway**.)

## Using it

1. **Add signatures**: click `+` in the left sidebar → pick one of:
   - **Type** — your name rendered in a handwriting font (4 styles to choose from)
   - **Draw** — freehand on a trackpad / mouse canvas
   - **Import** — PNG / JPEG / TIFF from disk
   - **Paste** — whatever image is on the clipboard (⌘V)
2. **Open a PDF**: ⌘O, or drag a PDF onto the window.
3. **Pick a signature** in the sidebar, then **click** on the PDF page to drop it.
4. **Drag** the signature to move it. **Drag the bottom-right corner handle** to resize (aspect ratio preserved).
5. Click the **×** in the corner of a placed signature to remove it.
6. Place as many signatures on as many pages as you need.
7. **Save signed PDF** (⌘S) — a file named `<original>_signed.pdf` is written next to the original, and Finder reveals it.

The signature library lives at `~/Library/Application Support/PDFHandler/signatures.json` (the image bytes are stored inline as PNG).

## Requirements

- macOS 13.0 (Ventura) or later.
- No external dependencies — no Ghostscript, no Python, nothing. Pure PDFKit.

## Build from source (terminal only, no Xcode IDE)

Only the Xcode **Command Line Tools** are required — not the full Xcode app.

```bash
xcode-select --install   # one-time
git clone https://github.com/blackswan83/pdfhandler.git
cd pdfhandler
./scripts/build-dmg.sh
# → build/PDFHandler-2.0.dmg
# → build/PDFHandler.app
```

What the script does:
1. `swift build -c release --product PDFHandler` to compile.
2. Assembles `PDFHandler.app/Contents/{MacOS,Info.plist,Resources,PkgInfo}`.
3. Ad-hoc codesigns with the bundled entitlements.
4. Packages into a `drag-to-Applications` DMG via `hdiutil`.

## Continuous builds (GitHub Actions)

`.github/workflows/build-dmg.yml` runs the script on every push and PR on a `macos-14` runner. Each run uploads the DMG as an artifact. On build failure, the last 200 lines of the compile log are posted as a PR comment. Pushing a `v*` tag additionally attaches the DMG to a GitHub Release.

```bash
git tag v2.0.0 && git push origin v2.0.0
# Release at github.com/<you>/pdfhandler/releases/tag/v2.0.0
```

## Project layout

```
.
├── scripts/build-dmg.sh              # compile + package
├── .github/workflows/build-dmg.yml   # CI
└── PDFHandler/
    ├── Package.swift                 # SwiftPM manifest
    ├── PDFHandler/
    │   ├── App/                      # PDFHandlerApp, AppState
    │   ├── Models/                   # Signature, SignaturePlacement
    │   ├── Services/                 # SignatureLibrary, PDFSigner
    │   ├── Views/                    # ContentView + sidebar + preview + sheets
    │   └── Resources/                # Info.plist, entitlements, Assets.xcassets
    └── PDFHandlerTests/
```

## Signing & sandboxing

- **Ad-hoc codesigned** (`codesign --sign -`): good enough to run locally.
- **Sandbox off**: the app writes the signed PDF next to the original. A Mac App Store build would turn on `com.apple.security.app-sandbox` + `com.apple.security.files.user-selected.read-write` and route saves through `NSSavePanel`.
- Full distribution requires an Apple Developer ID + notarization — out of scope for this repo.

## License

MIT — see [LICENSE](LICENSE).
