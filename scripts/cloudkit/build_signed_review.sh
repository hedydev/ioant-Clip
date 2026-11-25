#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export USER="$(id -un)"
export LOGNAME="$USER"
platform="$1"
mode="${2:-review}"
cacheLane=CloudKitReview
smoke=NO
ui=NO
conditions='$(inherited) CLIP_CLOUDKIT_REVIEW'
case "$mode" in
  review) ;;
  ui) [ "$platform" = macOS ] || exit 2
    cacheLane=CloudKitUIReview; ui=YES; conditions="$conditions CLIP_CLOUDKIT_UI_REVIEW";;
  smoke) [ "$platform" = macOS ] || exit 2
    cacheLane=CloudKitSmoke; smoke=YES; conditions="$conditions CLIP_CLOUDKIT_SMOKE";;
  *) exit 2;;
esac
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
  derived="$cache/projects/ioant-clip/DerivedData/$cacheLane/$platform"
else
  derived="$root/DerivedData/$cacheLane/$platform"
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
  "CLIP_CLOUDKIT_SMOKE=$smoke" "CLIP_CLOUDKIT_UI_REVIEW=$ui" "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$conditions" \
  build > "$log" 2>&1; then
  echo "BUILD SUCCEEDED $platform"
else
  echo "BUILD FAILED $platform"
  grep -E 'error:|warning:|BUILD FAILED' "$log" | tail -n 25 || true
  exit 1
fi
app="$derived/Build/Products/$product"
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/cloudkit/verify_signed_review.py "$platform" "$app" "$team" "$container"
if [ "$mode" = smoke ]; then
  [ "$(/usr/libexec/PlistBuddy -c 'Print :ClipCloudKitSmoke' "$app/Contents/Info.plist")" = YES ]
fi
if [ "$mode" = ui ]; then
  [ "$(/usr/libexec/PlistBuddy -c 'Print :ClipCloudKitUIReview' "$app/Contents/Info.plist")" = YES ]
  [ "$(/usr/libexec/PlistBuddy -c 'Print :ClipCloudKitSmoke' "$app/Contents/Info.plist")" = NO ]
fi
echo "Signed $mode artifact verified; not installed or launched"
