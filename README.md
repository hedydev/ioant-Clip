# ioant-Note — 0.2.0 prototype

A local-first macOS and iOS/iPadOS rich-content notebook. A clipboard paste creates a new note; browser captures preserve available rendered styles and can be imported as a new note. Merge creates a new note in oldest-to-newest order without deleting the originals. Tags, title edits, search, batch deletion, and local persistence are included in the source.

## Build on Mac

Requires macOS 14+, Xcode 15+ (with iOS 17+ SDK), and XcodeGen. Run from the repository:

    brew install xcodegen # only if missing
    xcodegen generate
    open ioant-Note.xcodeproj
    swift test

Select ioant-Note-macOS or ioant-Note-iOS. For an iPhone/iPad device, select your signing team in Xcode. macOS and generic iOS Simulator builds were verified for the R1 baseline; physical device installation is separate.

## Chrome / Edge extension (unpacked)

1. Open chrome://extensions (Edge: edge://extensions).
2. Enable Developer mode, choose Load unpacked, select BrowserExtension.
3. Visit a normal web page, e.g. a ChatGPT conversation. Click the extension, choose Save entire page or highlight text and choose Save selection.
4. For one-click import on macOS, run `python3 scripts/install_native_host.py --app /absolute/path/to/ioant-Note-macOS.app` once after building. This installs the exact extension ID allowlist in the Chrome native messaging directory and a private local host. For Edge, install separately with `--browser edge` if its profile is available and permitted. Reload the unpacked extension after updating. Capture is queued locally and the app opens in the background; it imports pending captures automatically. The extension acknowledges the queue, not a confirmed database write.
5. If direct import is unavailable, click Export capture file and manually import the .ioantnote.json file. Optionally choose Also copy styled HTML. Avoid manually importing a capture that has already been queued.

The extension has no persistent host permissions. It operates on the active tab after an explicit user click, uses local native messaging or explicit file export, and does not send page content to a service. On iOS the app can import the file via Files or paste normal clipboard content. Safari extension and cross-device sync are not implemented yet.

## Limitations

- Capture is a static snapshot of currently loaded DOM, including offscreen loaded content, not a crawler. Virtualized history, lazy/unloaded content, cross-origin frames, canvas/SVG/video and form values are not captured. Some external images cannot be embedded due to browser origin restrictions; original external fonts, complex layouts and interactive components may differ.
- Capture inlines selected computed styles and embeds accessible raster images within limits. Original links are retained as inert data attributes. The app disables JavaScript and uses sandboxed HTML with restrictive content security policies; rendering requires real WebKit validation.
- Maximum capture file size: 32 MiB. DOM and embedded image limits may truncate content, with a warning.
- App data is local JSON written atomically, no automatic backup or cloud synchronization. Merging duplicates the selected fragments and keeps originals. Delete requires confirmation.
- Browser end-to-end testing and real ChatGPT visual comparison remain separate acceptance steps.

## Git

SSH remote: git@github.com:hedydev/ioant-Note.git.

## High-fidelity capture (0.3)
On ChatGPT use Latest ChatGPT answer to capture the last loaded assistant message, or Selected content to capture an explicit range. Entire page remains available. For ordinary copy/paste workflow choose Copy styled content only, then paste in Note; direct native import retains the complete capture envelope and is recommended for diagrams. Capture uses computed styles, measured layout widths, SVG diagrams as restricted offline image documents, and available canvas/raster images. It is a static snapshot, not pixel-identical or interactive; cross-origin assets, unmounted messages and embedded external frames may be missing. An incomplete-assets warning is reported. Existing plain clipboard notes cannot recover data never copied.
