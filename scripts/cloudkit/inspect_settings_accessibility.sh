#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then derived="$cache/projects/ioant-clip/DerivedData"; else derived="$PWD/DerivedData"; fi
app="$derived/CloudKitCaptureExtensions/macOS/Build/Products/Debug/ioant-Clip-macOS.app"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
cp scripts/inspect_settings_accessibility.swift "$temp/main.swift"
/usr/bin/swiftc -swift-version 5 Sources/ClipCore/Capture/CaptureLanguage.swift "$temp/main.swift" -o "$temp/inspect-settings"
"$temp/inspect-settings" "$app" App/Localization/Localizable.xcstrings
