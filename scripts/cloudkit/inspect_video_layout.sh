#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
/usr/bin/swiftc -swift-version 5 $(find Sources/ClipCore -name "*.swift" -type f | sort) App/Platform/WebKit/PreviewWebView.swift scripts/cloudkit/inspect_video_layout.swift -o "$tmp/probe"
"$tmp/probe"
