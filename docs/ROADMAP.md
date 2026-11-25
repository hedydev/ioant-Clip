# Roadmap

1. Verify Xcode macOS/iOS builds and extension capture end-to-end against ChatGPT: headings, tables, fenced code, lists, images, long conversation and partial selections.
2. Improve capture fidelity: preserve dimensions responsively, handle additional allowed images/assets, represent missing dynamic content explicitly, optimize large note storage, improve merged note reading layout.
3. Integrate Chrome/Edge native messaging on macOS for one-click saving, with origin allowlist and explicit local user intent. Add Safari Web Extension for macOS and iOS using a shared capture engine; evaluate platform share-sheet integration.
4. Design optional synchronization only after the local data format and rendering are stable.

No background clipboard monitoring, cloud backend or AI processing in the initial release.

## Current priority (2026-11-26)
Validate actual Safari and iOS share capture, maintain iCloud-only sync stability, improve UI/localization, prepare physical-device and release acceptance. Google Drive transport remains in the repository but OAuth, enrollment and all further Google Drive development are paused at the owner's request. Do not change an existing cloud enrollment.
