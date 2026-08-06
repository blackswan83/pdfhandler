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

### Installing past Gatekeeper

The build is **ad-hoc signed** (no Apple Developer ID) and not notarized. Anything downloaded through a browser also carries a `com.apple.quarantine` flag, and quarantine plus an unidentified developer is what makes macOS claim the app is "damaged" or malware. Nothing is wrong with it — macOS simply has no signature to check it against.

Easiest route — mounts the DMG, installs, clears the flag, launches:

```bash
./scripts/install.sh ~/Downloads/PDFHandler-2.0.dmg
```

Or by hand: drag **PDFHandler.app** into **Applications**, then

```bash
find /Applications/PDFHandler.app -print0 | xargs -0 xattr -c
```

Recursion is required — the flag lands on nested files inside the bundle, and clearing only the top level can leave it blocked. Note this deliberately does **not** use `xattr -dr`: recent macOS ships a C `xattr` that dropped `-r` and answers `option -r not recognized`, so `find` does the recursion. Add `sudo` to both commands if you hit permission errors.

If macOS still calls it damaged after that, the ad-hoc signature itself may have been invalidated in transit. Re-seal it locally:

```bash
codesign --force --deep --sign - /Applications/PDFHandler.app
```

If macOS still refuses (Sequoia removed the old Control-click → Open bypass), approve it once in **System Settings → Privacy & Security → Open Anyway**.

**Permanent options, in ascending order of effort:**

- **Build locally.** Locally-built apps are never quarantined, so `./scripts/build-dmg.sh` followed by `./scripts/install.sh` sidesteps the whole thing.
- **Per-app Gatekeeper exception**, leaving Gatekeeper on for everything else:
  ```bash
  sudo spctl --add --label "PDF Handler" /Applications/PDFHandler.app
  ```
- **Apple Developer ID + notarization** (99 USD/year). The only route that makes the app open cleanly for anyone else, with no commands at all.

Disabling Gatekeeper globally (`spctl --master-disable`) also works, but it lowers the bar for *every* app on the machine — not worth it for one tool.

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
   - **Zoom** — ⌘+ / ⌘− to step, ⌘0 for actual size, ⌘9 to fit the window, or pinch on a trackpad. The toolbar shows the current level and lets you pick one directly. Zoom keeps the selected field centered, so you can zoom in to align a signature with a printed rule and nudge it into place.
   - Right-click for **Apply to every page** (handy for initials or a date stamp on long contracts).
5. ⌘Z / ⌘⇧Z to undo / redo.
6. ⌘S writes `<name>_signed.pdf` next to the original and reveals it in Finder. Fields are burned in permanently (flattened), so they show up in any PDF viewer.

Library lives at `~/Library/Application Support/PDFHandler/signatures.json`.

### Compress

Pick a PDF, choose a preset, optionally toggle grayscale, **Compress**. Output: `<name>_compressed.pdf` next to the source.

Turn on **Compress to a target size** to name a percentage of the original instead: the app runs several Ghostscript passes, binary-searching image resolution for the highest quality that still fits under the target, and reports the DPI it settled on. If even the most aggressive setting overshoots — normal for text-only PDFs, which have no images to shrink — it says so rather than pretending.

Beyond the stock presets (which only *name* a resolution), the app enables image downsampling, deduplicates repeated images, subsets fonts, and emits PDF 1.7 so the file structure itself is compressed. Bilevel scan content keeps a 300 DPI floor so scanned text stays legible even at aggressive settings.

**Digitally signed PDFs:** compression rewrites the file and therefore breaks its cryptographic signature — that is inherent to re-compression, not specific to this app. The app detects signed input and warns before you run it. The original is never modified.

Requires Ghostscript. The app looks for a copy bundled inside the app first, then at `/opt/homebrew/bin/gs`, `/usr/local/bin/gs`, `/usr/bin/gs`, `/opt/local/bin/gs`, `/sw/bin/gs`, or via `which gs`. If it's missing the compress pane shows a card with a one-click copy of:

```bash
brew install ghostscript
```

### Embedding Ghostscript (optional, personal builds)

To make Compress work with no Homebrew prerequisite on the machine you install to:

```bash
BUNDLE_GHOSTSCRIPT=1 ./scripts/build-dmg.sh
```

This vendors the `gs` on your build machine into the app: the executable into `Contents/MacOS/`, every non-system dylib it needs (transitively) into `Contents/Frameworks/` with load commands rewritten to `@executable_path`, and the `Resource/` tree into `Contents/Resources/ghostscript/`. Adds roughly 30–50 MB.

**It is off by default, deliberately.** Ghostscript is AGPLv3. Copyleft attaches to *distribution*, not to use — a build you make and install on your own machine carries no obligation whatsoever. But publishing the result to anyone else does: Artifex's position is that shipping Ghostscript with an application requires that application to be AGPL as well, or a commercial licence from them. This repo is MIT and its CI publishes release DMGs, so the default build produces no Ghostscript inside the app. Leave it that way unless you have relicensed the project or hold a commercial licence.

### Merge

Add PDFs (button or drag), drag rows to reorder, set the output name, **Merge**. Output: `<name>.pdf` next to the first source.

### Convert to Markdown

Pick a PDF, toggle options (YAML frontmatter, full-page images, OCR, OCR languages), **Convert**. Output: `<name>.md` next to the source (never overwriting an existing file), plus an optional companion `<name>_images/` directory of page images.

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
