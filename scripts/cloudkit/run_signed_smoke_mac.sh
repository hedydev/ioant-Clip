#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
cache="/Volumes/LunaDrive/DeveloperCache"
if [ -d "$cache" ] && [ -w "$cache" ]; then
  derived="$cache/projects/ioant-clip/DerivedData/CloudKitSmoke/macOS"
else
  derived="$root/DerivedData/CloudKitSmoke/macOS"
fi
app="$derived/Build/Products/Debug/ioant-Clip-macOS.app"
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/cloudkit/verify_signed_review.py macOS "$app" 64RS366WKG iCloud.com.ioant.clip
[ "$(/usr/libexec/PlistBuddy -c 'Print :ClipCloudKitSmoke' "$app/Contents/Info.plist")" = YES ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")" = ioant-Clip-macOS ]
# Direct executable invocation; no installation, LaunchServices or daily app access.
mode="${1:---clip-cloudkit-smoke}"
case "$mode" in
  --clip-cloudkit-smoke|--clip-cloudkit-account-check) [ "$#" -le 1 ];;
  --clip-cloudkit-resume) [ "$#" -eq 2 ]; exec "$app/Contents/MacOS/ioant-Clip-macOS" "$mode" "$2";;
  *) exit 2;;
esac
exec "$app/Contents/MacOS/ioant-Clip-macOS" "$mode"
