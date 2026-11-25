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
case "$platform" in macOS) dest="platform=macOS"; product="Debug/ioant-Clip-macOS.app";; iOS) dest="generic/platform=iOS"; product="Debug-iphoneos/ioant-Clip-iOS.app";; *) exit 2;; esac
python3 scripts/cloudkit/check_development_identity.py --team 64RS366WKG | grep '^PASS: Apple Development private-key signing'
log="$derived/$platform.log"
if ! xcodebuild -project ioant-Clip.xcodeproj -scheme "ioant-Clip-$platform" -configuration Debug -destination "$dest" -derivedDataPath "$derived/$platform" -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES build >"$log" 2>&1; then
  grep -E 'error:|warning:|BUILD FAILED' "$log" | tail -n 35 || true
  exit 1
fi
app="$derived/$platform/Build/Products/$product"
PYTHONDONTWRITEBYTECODE=1 python3 scripts/cloudkit/verify_signed_review.py "$platform" "$app" 64RS366WKG iCloud.com.ioant.clip
PYTHONDONTWRITEBYTECODE=1 python3 scripts/cloudkit/verify_capture_extensions.py "$platform" "$app"
