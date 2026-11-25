#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then derived="$cache/projects/ioant-clip/DerivedData"; else derived="$PWD/DerivedData"; fi
app="$derived/CloudKitCaptureExtensions/macOS/Build/Products/Debug/ioant-Clip-macOS.app"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
/usr/bin/swiftc -swift-version 5 Sources/ClipCore/Capture/CaptureLanguage.swift App/Localization/LanguagePreferences.swift scripts/verify_settings_locale.swift -o "$temp/settings-locale"
/usr/bin/env LANG=en_US.UTF-8 "$temp/settings-locale" "$app" App/Localization/Localizable.xcstrings
