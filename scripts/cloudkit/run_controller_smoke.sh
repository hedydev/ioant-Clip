#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then
  derived="$cache/projects/ioant-clip/DerivedData/CloudKitSmoke/macOS"
else
  derived="$root/DerivedData/CloudKitSmoke/macOS"
fi
app="$derived/Build/Products/Debug/ioant-Clip-macOS.app"
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/cloudkit/verify_signed_review.py macOS "$app" 64RS366WKG iCloud.com.ioant.clip
exec "$app/Contents/MacOS/ioant-Clip-macOS" --clip-controller-smoke
