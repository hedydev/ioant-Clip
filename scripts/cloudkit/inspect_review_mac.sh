#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then
  derived="$cache/projects/ioant-clip/DerivedData/CloudKitReview/macOS"
else
  derived="$PWD/DerivedData/CloudKitReview/macOS"
fi
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/cloudkit/inspect_review_profile.py macOS "$derived/Build/Products/Debug/ioant-Clip-macOS.app" 64RS366WKG iCloud.com.ioant.clip
