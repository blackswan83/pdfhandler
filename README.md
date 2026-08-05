# PDF Handler

A native macOS app for working with PDFs. Four modes in one window:

- **Sign** — DocuSign-style signing: a persistent library of signatures and initials, plus placeable **Date**, **Free-text**, **Checkbox** fields. Click to drop, drag to move, corner handle to resize. Apply any placement to every page, undo with ⌘Z.
- **Compress** — Ghostscript-backed compression with four presets (Prepress / Printer / eBook / Screen).
- **Merge** — combine multiple PDFs into one; drag to reorder.
- **To Markdown** — extract text to `.md`, with Vision OCR fallback for scanned pages. Optional companion `_images/` folder.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Download

Grab `PDFHandler-<version>.dmg` from either:

- **GitHub Releases** (attached automatically when a `v*` tag is pushed)
- **Actions → Build DMG → latest successful run → Artifacts** (built on every push)

Drag **PDFHandler.app** into **Applications**. Gatekeeper will block the first launch because the build is ad-hoc signed (no Apple Developer ID). Clear the flag once:

```bash
xattr -d com.apple.quarantine /Applications/PDFHandler.app
```

Then double-click to launch.

## Using it

### Sign

1. Click **+ Add signature…** (or **+ Add initials…**) in the sidebar. Pick one of:
   - **Type** — your name in a handwriting font (four styles).
   - **Draw** — freehand on a canvas.
   - **Import** — PNG / JPEG / TIFF from disk.
   - **Paste** — whatever image is on the clipboard (⌘V).
2. Open a PDF (⌘O, or drop it onto the window).
3. Pick a field type in the palette above the preview: **Signature**, **Initials**, **Date**, **Free text**, **Checkbox**.
4. Click on the page to drop a placement.
   - **Move** — drag the body. **Resize** — drag the corner knob (images and checkboxes keep their aspect; text boxes resize freely and the text scales with the box).
   - **Edit text** — double-click a Date or Free-text field, type, then press Return or click elsewhere.
   - **Keyboard** — ⌫ deletes the selected field, Esc deselects, arrow keys nudge by 1 pt (⇧-arrows by 10 pt).
   - Right-click for **Apply to every page** (handy for initials or a date stamp on long contracts).
5. ⌘Z / ⌘⇧Z to undo / redo.
6. ⌘S writes `<name>_signed.pdf` next to the original and reveals it in Finder. Fields are burned in permanently (flattened), so they show up in any PDF viewer.

Library lives at `~/Library/Application Support/PDFHandler/signatures.json`.

### Compress

Pick a PDF, choose a preset (slider nudges the preset automatically), optionally toggle grayscale / preserve metadata, **Compress**. Output: `<name>_compressed.pdf` next to the source.

Requires Ghostscript. The app detects it automatically at `/opt/homebrew/bin/gs`, `/usr/local/bin/gs`, `/usr/bin/gs`, `/opt/local/bin/gs`, `/sw/bin/gs`, or via `which gs`. If it's missing the compress pane shows a card with a one-click copy of:

```bash
brew install ghostscript
```

### Merge

Add PDFs (button or drag), drag rows to reorder, set the output name, **Merge**. Output: `<name>.pdf` next to the first source.

### Convert to Markdown

Pick a PDF, toggle options (YAML frontmatter, extract images, OCR, OCR languages, table fallback), **Convert**. Output: `<name>.md` next to the source plus a companion `<name>_images/` directory of figures.

OCR is Vision-based; it kicks in only for pages whose text layer is empty / very short. No cloud calls.

## Requirements

- macOS 13.0 (Ventura) or later
- [Ghostscript](https://www.ghostscript.com/) for the Compress tab only — everything else works out of the box.

## Build from source (terminal only)

Only the Xcode Command Line Tools are required — not the full Xcode app.

```bash
xcode-select --install   # one-time
git clone https://github.com/blackswan83/pdfhandler.git
cd pdfhandler
./scripts/build-dmg.sh
# → build/PDFHandler-<version>.dmg
# → build/PDFHandler.app
```

The script:
1. Renders the app icon by running `scripts/render-icon.swift` with CoreGraphics (1024×1024 master → `sips` into all 10 Contents.json sizes).
2. `swift build -c release --product PDFHandler`.
3. Assembles `Contents/{MacOS, Info.plist, Resources, PkgInfo}`.
4. `actool` compiles the asset catalog into `Assets.car`.
5. Ad-hoc codesigns with the bundled entitlements.
6. Packages into a drag-to-Applications DMG via `hdiutil`.

## Continuous builds

`.github/workflows/build-dmg.yml` runs the script on `macos-14` on every push and PR. Each run uploads the DMG as an artifact. On failure the last 200 log lines are auto-posted as a PR comment. Pushing a `v*` tag attaches the DMG to a GitHub Release.

```bash
git tag v3.0.0 && git push origin v3.0.0
```

## Project layout

```
.
├── scripts/
│   ├── build-dmg.sh           # compile + package
│   └── render-icon.swift      # deterministic icon renderer
├── .github/workflows/
│   └── build-dmg.yml          # CI
└── PDFHandler/
    ├── Package.swift
    ├── PDFHandler/
    │   ├── App/               # PDFHandlerApp, AppState
    │   ├── Models/            # Signature, Placement
    │   ├── Services/          # SignatureLibrary, PDFFlattener,
    │   │                      # CompressionService, PDFMerger,
    │   │                      # MarkdownConverter, PDFPageRenderer,
    │   │                      # UndoCoordinator
    │   ├── Views/             # ContentView, SignWorkspaceView,
    │   │                      # LibrarySidebarView, FieldToolbarView,
    │   │                      # PDFPreviewView, PlacementView,
    │   │                      # NewSignatureView, SignatureCanvasView,
    │   │                      # CompressView, MergeView, ConvertView
    │   └── Resources/         # Info.plist, entitlements, Assets.xcassets
    └── PDFHandlerTests/
```

## Signing & sandboxing

- **Ad-hoc codesigned** (`codesign --sign -`) — good enough to run locally.
- **Sandbox off** so the app can write `<name>_signed.pdf`, `<name>_compressed.pdf`, merged PDFs, and the Markdown output next to originals.
- Mac App Store distribution would turn the sandbox on and route saves through `NSSavePanel`; full distribution requires an Apple Developer ID + notarization. Out of scope for this repo.

## License

MIT — see [LICENSE](LICENSE).
