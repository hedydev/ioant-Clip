#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export USER="$(id -un)"
export LOGNAME="$USER"
platform="$1"
team=64RS366WKG
container=iCloud.com.ioant.clip
case "$platform" in
  macOS) destination="platform=macOS"; product="Debug/ioant-Clip-macOS.app";;
  iOS) destination="generic/platform=iOS"; product="Debug-iphoneos/ioant-Clip-iOS.app";;
  *) exit 2;;
esac
# Do not authorize automatic provisioning if the existing development identity
# cannot be located. No certificate creation/revocation commands are used.
probe="$(/usr/bin/python3 scripts/cloudkit/check_development_identity.py --team "$team")"
printf '%s\n' "$probe"
printf '%s\n' "$probe" | grep -q '^PASS: Apple Development private-key signing'
xcodegen generate
root="$PWD"
cache="/Volumes/LunaDrive/DeveloperCache"
if [ -d "$cache" ] && [ -w "$cache" ]; then
  derived="$cache/projects/ioant-clip/DerivedData/CloudKitReview/$platform"
else
  derived="$root/DerivedData/CloudKitReview/$platform"
fi
mkdir -p "$derived"
log="$derived/signed-review.log"
echo "BEGIN signed CloudKit development review $platform"
# Scoped to the existing registered Clip targets; does not register devices,
# install, launch, or contact CloudKit itself.
if xcodebuild -project ioant-Clip.xcodeproj -scheme "ioant-Clip-$platform" -configuration Debug \
  -destination "$destination" -derivedDataPath "$derived" -allowProvisioningUpdates \
  "DEVELOPMENT_TEAM=$team" "CODE_SIGN_STYLE=Automatic" "CODE_SIGN_IDENTITY=Apple Development" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  "CLIP_CLOUDKIT_CONTAINER=$container" "CODE_SIGN_ENTITLEMENTS=$root/Config/CloudKitReview.entitlements" \
  "INFOPLIST_FILE=$root/Config/CloudKitReview-Info.plist" \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CLIP_CLOUDKIT_REVIEW' \
  build > "$log" 2>&1; then
  echo "BUILD SUCCEEDED $platform"
else
  echo "BUILD FAILED $platform"
  grep -E 'error:|warning:|BUILD FAILED' "$log" | tail -n 25 || true
  exit 1
fi
app="$derived/Build/Products/$product"
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/cloudkit/verify_signed_review.py "$platform" "$app" "$team" "$container"
echo "Signed review artifact verified; not installed or launched"
