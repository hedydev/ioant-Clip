#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 - <<'PY'
import json, os, pathlib, stat
support = pathlib.Path.home() / "Library/Application Support"
for relative in ("ioant-Clip/NativeMessaging/config.json", "ioant-Note/NativeMessaging/config.json", "Google/Chrome/NativeMessagingHosts/com.ioant.clip.capture.json", "Google/Chrome/NativeMessagingHosts/com.ioant.note.capture.json"):
    path = support / relative
    try:
        info = path.lstat()
        print(relative, "regular:", stat.S_ISREG(info.st_mode), "symlink:", stat.S_ISLNK(info.st_mode))
        if not stat.S_ISREG(info.st_mode): continue
        obj = json.loads(path.read_text())
        for key in ("app_path", "path"):
            if key in obj:
                target = pathlib.Path(obj[key])
                print("  ", key, str(target), "exists:", target.exists())
        print("   origins count:", len(obj.get("allowed_origins", [])))
    except FileNotFoundError:
        print(relative, "missing")
    except PermissionError:
        print(relative, "permission denied")
    except (ValueError, OSError, TypeError) as error:
        print(relative, type(error).__name__)
PY
