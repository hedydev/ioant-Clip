# ioant-Note engineering entry

Product: local-first macOS/iOS rich-content notes, clipboard and browser capture, selection/page capture, note merging, tags, search and deletion. Preserve source fragments and user data. No automatic clipboard monitoring or cloud upload. User chooses capture explicitly. Browser captures are untrusted and must be rendered offline without script execution or network access.

Read .hero-skills.yaml and the pinned Hero staged execution and development governance before dependent work. Use the independently registered MCP project, exact committed source, deterministic scripts and durable receipts. Do not reset, stash, clean, switch branches, overwrite local edits or delete user data. Avoid running unrelated simulators. Tests that launch devices must track only their own UDIDs and clean up on all outcomes; do not shut down user-owned simulators.

Build: swift test; node --check BrowserExtension/popup.js; xcodegen generate; xcodebuild for macOS and generic iOS Simulator (no boot). See scripts/validate.sh. App release and physical-device installation are separate acceptance steps.

First milestone: verify existing prototype builds, then implement direct capture and validate real ChatGPT fidelity before Safari or sync. See docs/ROADMAP.md.
