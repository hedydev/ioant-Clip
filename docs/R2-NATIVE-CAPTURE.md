# R2 — One-click browser capture

Capture on explicit click -> native messaging (allowlisted stable unpacked extension ID) -> atomically write private UUID JSON inbox -> app imports into persistent NoteLibrary -> delete inbox file only after durable save. A replay after save is deduplicated by note UUID. Host opens configured app in background; if unavailable file remains queued. No HTTP listener, cloud upload or remote requests. Explicit export fallback. Queue acknowledgement is not a library acknowledgement.

Validation: Swift inbox tests, Python native protocol framing/allowlist/install tests, extension JS syntax, Apple platform builds. Real Chrome/Edge integration and visual fidelity require separate browser acceptance. Current implementation is macOS-only for direct native capture; iOS uses clipboard/file import.
