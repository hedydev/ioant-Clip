#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
/usr/bin/swiftc -swift-version 5 Sources/ClipCore/Capture/CaptureLanguage.swift App/Localization/LanguagePreferences.swift scripts/test_language_preferences.swift -o "$tmp/lang-test"
"$tmp/lang-test"
