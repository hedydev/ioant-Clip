#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then
  derived="$cache/projects/ioant-clip/DerivedData"
else
  derived="$PWD/DerivedData"
fi
app="$derived/CloudKitUIReview/macOS/Build/Products/Debug/ioant-Clip-macOS.app"
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/cloudkit/verify_signed_review.py macOS "$app" 64RS366WKG iCloud.com.ioant.clip
/usr/bin/swift scripts/cloudkit/launch_ui_review_mac.swift "$app"
