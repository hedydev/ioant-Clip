#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then derived="$cache/projects/ioant-clip/DerivedData"; else derived="$PWD/DerivedData"; fi
app="$derived/CloudKitCaptureExtensions/macOS/Build/Products/Debug/ioant-Clip-macOS.app"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
/usr/bin/swiftc -parse-as-library scripts/cloudkit/close_inbox_alert.swift -o "$temp/close-inbox-alert"
"$temp/close-inbox-alert" "$app"
bash scripts/cloudkit/activate_capture_extensions_mac.sh
