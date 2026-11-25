#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then derived="$cache/projects/ioant-clip/DerivedData"; else derived="$PWD/DerivedData"; fi
app="$derived/CloudKitCaptureExtensions/macOS/Build/Products/Debug/ioant-Clip-macOS.app"
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/cloudkit/verify_signed_review.py macOS "$app" 64RS366WKG iCloud.com.ioant.clip
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/cloudkit/verify_capture_extensions.py macOS "$app"
tmp="$(mktemp -d)"
trap 'rm -f "$tmp/restart-clip"; rmdir "$tmp"' EXIT
/usr/bin/swiftc -parse-as-library scripts/cloudkit/restart_blocked_clip.swift -o "$tmp/restart-clip"
"$tmp/restart-clip" "$app"
bash scripts/cloudkit/activate_capture_extensions_mac.sh
