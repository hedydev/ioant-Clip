#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export USER="$(id -un)" LOGNAME="$(id -un)"
xcodegen generate
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then
  derived="$cache/projects/ioant-clip/DerivedData/AppIconRelease"
else
  derived="$PWD/DerivedData/AppIconRelease"
fi
mkdir -p "$derived"
log="$derived/build.log"
if ! xcodebuild -project ioant-Clip.xcodeproj -scheme ioant-Clip-iOS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO build >"$log" 2>&1; then
  grep -E 'error:|warning:|BUILD FAILED' "$log" | tail -n 35 || true
  exit 1
fi
python3 scripts/test_app_icons.py "$derived/Build/Products/Release-iphoneos/ioant-Clip-iOS.app"
