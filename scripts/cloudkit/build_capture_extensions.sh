#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export USER="$(id -un)" LOGNAME="$(id -un)"
root="$PWD"
python3 scripts/prepare_capture_extensions.py
# XcodeGen resolves relative paths from the spec; --project controls output.
# Generate a root-level spec through a temporary, ignored file.
spec="$root/.clip-extension-build.yml"
test ! -e "$spec"
trap 'rm -f "$spec"' EXIT
cp GeneratedExtensions/project.yml "$spec"
xcodegen generate --spec "$spec"
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then derived="$cache/projects/ioant-clip/DerivedData/CloudKitCaptureExtensions"; else derived="$root/DerivedData/CloudKitCaptureExtensions"; fi
mkdir -p "$derived"
platform="$1"
lane="$platform"
scheme="ioant-Clip-$platform"
case "$platform" in
  macOS) dest="platform=macOS"; product="Debug/ioant-Clip-macOS.app";;
  iOS) dest="generic/platform=iOS"; product="Debug-iphoneos/ioant-Clip-iOS.app";;
  simulator) lane=SimulatorConversationAttachments; scheme=ioant-Clip-iOS; dest="generic/platform=iOS Simulator"; product="Debug-iphonesimulator/ioant-Clip-iOS.app";;
  *) exit 2;;
esac
if [ "$platform" = simulator ]; then
  signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES)
else
  python3 scripts/cloudkit/check_development_identity.py --team 64RS366WKG | grep '^PASS: Apple Development private-key signing'
  signing=(-allowProvisioningUpdates CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES)
fi
log="$derived/$lane.log"
if ! xcodebuild -project ioant-Clip.xcodeproj -scheme "$scheme" -configuration Debug -destination "$dest" -derivedDataPath "$derived/$lane" "${signing[@]}" build >"$log" 2>&1; then
  grep -E 'error:|warning:|BUILD FAILED' "$log" | tail -n 35 || true
  exit 1
fi
app="$derived/$lane/Build/Products/$product"
if [ "$platform" = simulator ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 scripts/cloudkit/verify_simulator_smoke.py "$app" com.ioant.clip.ios development
else
  PYTHONDONTWRITEBYTECODE=1 python3 scripts/cloudkit/verify_signed_review.py "$platform" "$app" 64RS366WKG iCloud.com.ioant.clip
fi
PYTHONDONTWRITEBYTECODE=1 python3 scripts/cloudkit/verify_capture_extensions.py "$platform" "$app"
