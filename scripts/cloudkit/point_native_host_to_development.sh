#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 - <<'PY'
import json, os, pathlib, plistlib, sys
sys.path.insert(0, "scripts")
from install_native_host import extension_id, atomic_json
root = pathlib.Path.cwd()
cache = pathlib.Path("/Volumes/LunaDrive/DeveloperCache")
derived = cache / "projects/ioant-clip/DerivedData" if cache.is_dir() and os.access(cache, os.W_OK) else root / "DerivedData"
app = derived / "CloudKitDevelopment/macOS/Build/Products/Debug/ioant-Clip-macOS.app"
old = derived / "macOS/Build/Products/Debug/ioant-Clip-macOS.app"
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info.get("CFBundleIdentifier") == "com.ioant.clip.macos" and info.get("ClipCloudKitDevelopment") == "YES"
config = pathlib.Path.home() / "Library/Application Support/ioant-Clip/NativeMessaging/config.json"
assert config.is_file() and not config.is_symlink(), "Existing project host config unavailable"
value = json.loads(config.read_text())
assert value.get("allowed_origins") == ["chrome-extension://" + extension_id() + "/"], "Unexpected extension origin"
assert pathlib.Path(value["app_path"]).resolve() in (app.resolve(), old.resolve()), "Unexpected old host app path"
os.umask(0o077)
value["app_path"] = str(app.resolve())
atomic_json(config, value)
assert json.loads(config.read_text()) == value
print("PASS: existing native host now targets signed development app; same origin and daily inbox; no Chrome settings modified")
PY
