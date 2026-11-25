# ioant-Note — 0.1.0 prototype

A local-first macOS and iOS/iPadOS rich-content notebook. A clipboard paste creates a new note; browser captures preserve available rendered styles and can be imported as a new note. Merge creates a new note in oldest-to-newest order without deleting the originals. Tags, title edits, search, batch deletion, and local persistence are included in the source.

## Build on Mac

Requires macOS 14+, Xcode 15+ (with iOS 17+ SDK), and XcodeGen. Run from the repository:

    brew install xcodegen # only if missing
    xcodegen generate
    open ioant-Note.xcodeproj
    swift test

Select ioant-Note-macOS or ioant-Note-iOS. For an iPhone/iPad device, select your signing team in Xcode. Simulator and Apple platform builds have not yet been validated.

## Chrome / Edge extension (unpacked)

1. Open chrome://extensions (Edge: edge://extensions).
2. Enable Developer mode, choose Load unpacked, select BrowserExtension.
3. Visit a normal web page, e.g. a ChatGPT conversation. Click the extension, choose Save entire page or highlight text and choose Save selection.
4. In ioant-Note, select Import web capture and pick the downloaded .ioantnote.json file. Optionally choose Also copy styled HTML in the extension, then paste in the app.

The extension has no persistent host permissions. It operates on the active tab after an explicit user click, saves a local file, and does not send page content to a service. On iOS the app can import the file via Files or paste normal clipboard content. Safari extension, direct native messaging and cross-device sync are not implemented yet.

## Limitations

- Capture is a static snapshot of currently loaded DOM, including offscreen loaded content, not a crawler. Virtualized history, lazy/unloaded content, cross-origin frames, canvas/SVG/video and form values are not captured. Some external images cannot be embedded due to browser origin restrictions; original external fonts, complex layouts and interactive components may differ.
- Capture inlines selected computed styles and embeds accessible raster images within limits. Original links are retained as inert data attributes. The app disables JavaScript and uses sandboxed HTML with restrictive content security policies; rendering requires real WebKit validation.
- Maximum capture file size: 32 MiB. DOM and embedded image limits may truncate content, with a warning.
- App data is local JSON written atomically, no automatic backup or cloud synchronization. Merging duplicates the selected fragments and keeps originals. Delete requires confirmation.
- Source prototype: the original archive passed Swift core tests and JS syntax checks, but no macOS/iOS build, browser end-to-end test, or real ChatGPT visual comparison has been performed.

## Git

SSH remote: git@github.com:hedydev/ioant-Note.git.
