#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -d /Volumes/LunaDrive/DeveloperCache ] && [ -w /Volumes/LunaDrive/DeveloperCache ]; then
  derived="/Volumes/LunaDrive/DeveloperCache/projects/ioant-clip/DerivedData"
else
  derived="$PWD/DerivedData"
fi
app="$derived/CloudKitDevelopment/macOS/Build/Products/Debug/ioant-Clip-macOS.app"
test -d "$app"
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/cloudkit/verify_signed_review.py macOS "$app" 64RS366WKG iCloud.com.ioant.clip
/usr/bin/swift scripts/relaunch_mac.swift "$app" "$derived" "${1:-normal}"
