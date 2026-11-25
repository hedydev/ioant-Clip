#!/bin/bash
set -u
cd "$(dirname "$0")/.." || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export USER="$(id -un)"
export LOGNAME="$USER"
echo "HEAD $(git rev-parse HEAD)"
origin="$(git remote get-url origin)"
case "$origin" in
  git@github.com:hedydev/ioant-Note.git|ssh://git@github.com/hedydev/ioant-Note.git) echo "origin: expected SSH remote";;
  *) echo "origin: not expected SSH URL"; exit 1;;
esac
git diff --check || exit 1
xcodebuild -version || exit 1
swift --version
status=0
swift test || status=1
/usr/bin/python3 scripts/test_localization.py || status=1
bash scripts/test_language_preferences.sh || status=1
/usr/bin/python3 scripts/test_extension_localization.py || status=1
bash scripts/test_webkit_render.sh || status=1
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/test_native_host.py || status=1
if command -v node >/dev/null; then
  for source in BrowserExtension/Popup/*.js; do node --check "$source" || status=1; done
  /usr/bin/python3 scripts/build_capture_bundle.py --check || status=1
  for source in BrowserExtension/CaptureEngine/*.js; do node --check "$source" || status=1; done
  node --check BrowserExtension/CaptureEngine/viewport.js || status=1
  node scripts/test_viewport.js || status=1
  /usr/bin/python3 scripts/test_page_layout.py || status=1
  /usr/bin/python3 scripts/test_capture_browser.py || status=1
else
  echo "Node unavailable: extension syntax check not run"; status=1
fi
if ! command -v xcodegen >/dev/null; then
  echo "BLOCKED: XcodeGen is not installed; native builds not run."
  exit 1
fi
xcodegen generate || exit 1
root="$PWD"
if [ -d /Volumes/LunaDrive/DeveloperCache ] && [ -w /Volumes/LunaDrive/DeveloperCache ]; then
  derived="/Volumes/LunaDrive/DeveloperCache/projects/ioant-note/DerivedData"
else
  derived="$root/DerivedData"
fi
mkdir -p "$derived" || exit 1
echo "DerivedData: $derived"
for platform in macOS iOS; do
  case "$platform" in
    macOS) dest="platform=macOS";;
    iOS) dest="generic/platform=iOS Simulator";;
  esac
  echo "BEGIN BUILD $platform"
  xcodebuild -project ioant-Note.xcodeproj -scheme "ioant-Note-$platform" -destination "$dest" -derivedDataPath "$derived/$platform" CODE_SIGNING_ALLOWED=NO build > "$derived/$platform.log" 2>&1
  rc=$?
  grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)' "$derived/$platform.log" | tail -n 35 || true
  echo "END BUILD $platform exit=$rc"
  if [ "$rc" -ne 0 ]; then tail -n 35 "$derived/$platform.log"; status=1; else
    case "$platform" in macOS) app="$derived/macOS/Build/Products/Debug/ioant-Note-macOS.app";; iOS) app="$derived/iOS/Build/Products/Debug-iphonesimulator/ioant-Note-iOS.app";; esac
    /usr/bin/python3 scripts/test_localization.py "$app" || status=1
  fi
done
exit "$status"
