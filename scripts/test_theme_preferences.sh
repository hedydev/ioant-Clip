#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
/usr/bin/swiftc -swift-version 5 App/DesignSystem/Theme/ThemePreferences.swift scripts/test_theme_preferences.swift -o "$tmp/theme-test"
"$tmp/theme-test"
