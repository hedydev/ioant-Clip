# ioant-Clip engineering entry

Product: local-first macOS/iOS rich-content notes, clipboard and browser capture, selection/page capture, note merging, tags, search and deletion. Preserve source fragments and user data. No automatic clipboard monitoring or cloud upload. User chooses capture explicitly. Browser captures are untrusted and must be rendered offline without script execution or network access.

Read .hero-skills.yaml and the pinned Hero staged execution and development governance before dependent work. Use the independently registered MCP project, exact committed source, deterministic scripts and durable receipts. Do not reset, stash, clean, switch branches, overwrite local edits or delete user data. Avoid running unrelated simulators. Tests that launch devices must track only their own UDIDs and clean up on all outcomes; do not shut down user-owned simulators.

Build: swift test; node --check BrowserExtension/popup.js; xcodegen generate; xcodebuild for macOS and generic iOS Simulator (no boot). See scripts/validate.sh. App release and physical-device installation are separate acceptance steps.

Current priority: modularization, internationalization (en, zh-Hans, zh-Hant, ja, ko), theme, native UI refinement, then cloud sync. Keep original SwiftUI navigation, sheets, gestures and native motion. Preserve existing bundle IDs, data paths, serialized schema and browser host identity. See docs/ROADMAP.md.
