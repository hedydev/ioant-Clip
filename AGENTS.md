# ioant-Clip engineering entry

Product: local-first macOS/iOS rich-content notes, clipboard and browser capture, selection/page capture, note merging, tags, search and deletion. Preserve source fragments and user data. No automatic clipboard monitoring or cloud upload. User chooses capture explicitly. Browser captures are untrusted and must be rendered offline without script execution or network access.

Read .hero-skills.yaml and the pinned Hero staged execution and development governance before dependent work. Use the independently registered MCP project, exact committed source, deterministic scripts and durable receipts. Do not reset, stash, clean, switch branches, overwrite local edits or delete user data. Avoid running unrelated simulators. Tests that launch devices must track only their own UDIDs and clean up on all outcomes; do not shut down user-owned simulators.

Build: swift test; node --check BrowserExtension/Popup/popup.js; xcodegen generate; xcodebuild for macOS and generic iOS Simulator (no boot). See scripts/validate.sh. App release and physical-device installation are separate acceptance steps.

Current priority: modularization, internationalization (en, zh-Hans, zh-Hant, ja, ko), theme, native UI refinement, then cloud sync. Keep original SwiftUI navigation, sheets, gestures and native motion. Use current product IDs com.ioant.clip.macos / com.ioant.clip.ios and ClipCore. Preserve existing persisted schema and daily data paths, browser extension key and legacy native messaging alias; repository/MCP binding changes are separate. See docs/ROADMAP.md.

## Window and modal UI
Use `App/DesignSystem/Presentation/ClipSheet.swift` and `ModalScrollPage` for all feature sheets. Shared `PresentationMetrics` owns window/sheet sizes and margins; no per-feature arbitrary fixed modal sizes or macOS two-column Form for long content. Keep system sheet/navigation transitions and actions; let page content scroll and wrap. See docs/ARCHITECTURE.md.
