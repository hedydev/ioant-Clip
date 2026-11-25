#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
/usr/bin/swiftc -swift-version 5 Sources/NoteCore/Note.swift Sources/NoteCore/Tags.swift Sources/NoteCore/SyncJournal.swift App/PreviewWebView.swift scripts/webkit_render_test.swift -o "$tmp/render-test"
"$tmp/render-test"
