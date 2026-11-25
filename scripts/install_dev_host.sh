#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -d /Volumes/LunaDrive/DeveloperCache ] && [ -w /Volumes/LunaDrive/DeveloperCache ]; then
  derived="/Volumes/LunaDrive/DeveloperCache/projects/ioant-note/DerivedData"
else
  derived="$PWD/DerivedData"
fi
app="$derived/macOS/Build/Products/Debug/ioant-Note-macOS.app"
test -d "$app"
echo "HEAD $(git rev-parse HEAD)"
/usr/bin/python3 scripts/install_native_host.py --app "$app"
# Verify only our own Chrome registration manifest and executable; do not read other browser settings.
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 - <<'PY'
import json, os, pathlib
support = pathlib.Path.home() / "Library/Application Support"
config = json.loads((support/"ioant-Note/NativeMessaging/config.json").read_text())
for browser in ("Google/Chrome",):
    manifest = json.loads((support/browser/"NativeMessagingHosts/com.ioant.note.capture.json").read_text())
    assert manifest["allowed_origins"] == config["allowed_origins"]
    assert manifest["name"] == "com.ioant.note.capture"
    assert os.access(manifest["path"], os.X_OK)
    print(browser + ": registration verified")
assert pathlib.Path(config["app_path"]).is_dir()
print("App bundle verified; no synthetic captures inserted.")
PY
