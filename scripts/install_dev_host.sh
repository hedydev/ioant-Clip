#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -d /Volumes/LunaDrive/DeveloperCache ] && [ -w /Volumes/LunaDrive/DeveloperCache ]; then
  derived="/Volumes/LunaDrive/DeveloperCache/projects/ioant-clip/DerivedData"
else
  derived="$PWD/DerivedData"
fi
app="$derived/CloudKitDevelopment/macOS/Build/Products/Debug/ioant-Clip-macOS.app"
test -d "$app"
echo "HEAD $(git rev-parse HEAD)"
/usr/bin/python3 scripts/install_native_host.py --app "$app"
# Verify only our own Chrome registration manifest and executable; do not read other browser settings.
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 - <<'PY'
import json, os, pathlib
support = pathlib.Path.home() / "Library/Application Support"
config = json.loads((support/"ioant-Clip/NativeMessaging/config.json").read_text())
for browser in ("Google/Chrome",):
    for name in ("com.ioant.clip.capture", "com.ioant.note.capture"):
        manifest = json.loads((support/browser/"NativeMessagingHosts"/(name+".json")).read_text())
        assert manifest["allowed_origins"] == config["allowed_origins"]
        assert manifest["name"] == name
        assert os.access(manifest["path"], os.X_OK)
        print(browser + ": " + name + " registration verified")
assert pathlib.Path(config["app_path"]).is_dir()
print("App bundle verified; no synthetic captures inserted.")
PY
