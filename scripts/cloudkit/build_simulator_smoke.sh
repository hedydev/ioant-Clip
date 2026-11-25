#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export USER="$(id -un)"
export LOGNAME="$USER"
root="$PWD"
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then
  derived="$cache/projects/ioant-clip/DerivedData/CloudKitSmoke/Simulator"
else
  derived="$root/DerivedData/CloudKitSmoke/Simulator"
fi
mkdir -p "$derived"
xcodegen generate
log="$derived/build.log"
# Simulator-only identity, no portal registration or provisioning updates.
if ! xcodebuild -project ioant-Clip.xcodeproj -scheme ioant-Clip-iOS -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
  PRODUCT_BUNDLE_IDENTIFIER=com.ioant.clip.ios.simsmoke \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  DEVELOPMENT_TEAM=64RS366WKG \
  CLIP_CLOUDKIT_CONTAINER=iCloud.com.ioant.clip CLIP_CLOUDKIT_SMOKE=YES \
  "CODE_SIGN_ENTITLEMENTS=$root/Config/CloudKitReview.entitlements" \
  "INFOPLIST_FILE=$root/Config/CloudKitReview-Info.plist" \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CLIP_CLOUDKIT_REVIEW CLIP_CLOUDKIT_SIM_SMOKE' \
  build > "$log" 2>&1; then
  grep -E 'error:|warning:|BUILD FAILED' "$log" | tail -n 30 || true
  exit 1
fi
/usr/bin/python3 scripts/cloudkit/verify_simulator_smoke.py "$derived/Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
