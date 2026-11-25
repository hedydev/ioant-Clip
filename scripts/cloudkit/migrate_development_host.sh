#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Use the existing scoped installer; do not touch unrelated Chrome settings.
bash scripts/install_dev_host.sh
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 - <<'PY'
import json, os, pathlib, sys
sys.path.insert(0, "scripts")
from install_native_host import extension_id, atomic_json
support = pathlib.Path.home() / "Library/Application Support"
old = support / "ioant-Note/NativeMessaging/config.json"
new = support / "ioant-Clip/NativeMessaging/config.json"
assert old.is_file() and not old.is_symlink()
assert new.is_file() and not new.is_symlink()
previous = json.loads(old.read_text())
current = json.loads(new.read_text())
assert previous.get("allowed_origins") == current.get("allowed_origins") == ["chrome-extension://" + extension_id() + "/"]
expected = pathlib.Path("/Volumes/LunaDrive/DeveloperCache/projects/ioant-note/DerivedData/macOS/Build/Products/Debug/ioant-Note-macOS.app")
assert pathlib.Path(previous["app_path"]).resolve() in (expected.resolve(), pathlib.Path(current["app_path"]).resolve())
# Preserve legacy host executable and inbox, only redirect its own app target.
os.umask(0o077)
previous["app_path"] = current["app_path"]
atomic_json(old, previous)
assert json.loads(old.read_text()) == previous
print("PASS: legacy host target also updated; no captures inserted")
PY
