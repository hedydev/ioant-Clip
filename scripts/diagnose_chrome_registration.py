#!/usr/bin/env python3
"""Read only Clip registration fields, never browser history, tabs or secrets."""
import base64, hashlib, json, os, pathlib, re, plistlib
root = pathlib.Path(__file__).resolve().parents[1]
manifest = json.loads((root / "BrowserExtension/manifest.json").read_text())
extension_id = hashlib.sha256(base64.b64decode(manifest["key"], validate=True)).hexdigest()[:32].translate(str.maketrans("0123456789abcdef", "abcdefghijklmnop"))
expected = root / "BrowserExtension"
popup = pathlib.Path(manifest["action"]["default_popup"])
assert (expected / popup).is_file()
support = pathlib.Path.home() / "Library/Application Support"
chrome = support / "Google/Chrome"
print("Extension ID:", extension_id, flush=True)
print("Expected unpacked directory:", expected, flush=True)
found = 0
# Read only the project-specific registration from normal Chrome profiles.
for profile in sorted(chrome.iterdir()) if chrome.is_dir() else []:
    if not re.fullmatch(r"Default|Profile [0-9]+", profile.name) or profile.is_symlink(): continue
    for filename in ("Preferences", "Secure Preferences"):
        path = profile / filename
        if not path.is_file() or path.is_symlink(): continue
        try:
            entry = json.loads(path.read_text()).get("extensions", {}).get("settings", {}).get(extension_id)
        except (OSError, ValueError, AttributeError):
            print("Unable to inspect", profile.name, filename, flush=True); continue
        if not isinstance(entry, dict): continue
        found += 1
        raw = entry.get("path")
        actual = pathlib.Path(raw) if isinstance(raw, str) else None
        if actual is not None and not actual.is_absolute(): actual = profile / "Extensions" / actual
        # Never report an unrelated full path; identify only expected/old path.
        old = root.parent / "ioant-Note" / "BrowserExtension"
        status = "unrecognized"
        if actual is not None:
            if actual == expected: status = "current repository path"
            elif actual == old: status = "old repository path"
            else: status = "other registered path"
        print(profile.name, filename, status, "popup exists:", bool(actual and (actual / popup).is_file()), flush=True)
print("Matching registrations:", found, flush=True)
for name in ("com.ioant.clip.capture", "com.ioant.note.capture"):
    path = chrome / "NativeMessagingHosts" / (name + ".json")
    if not path.is_file():
        print(name, "missing manifest", flush=True); continue
    try:
        h = json.loads(path.read_text())
        print(name, "origin matches:", h.get("allowed_origins") == ["chrome-extension://" + extension_id + "/"], "host executable:", os.access(h.get("path", ""), os.X_OK), flush=True)
    except (OSError, ValueError, TypeError):
        print(name, "invalid manifest", flush=True)
config = support / "ioant-Clip/NativeMessaging/config.json"
if config.is_file():
    try:
        conf = json.loads(config.read_text())
        app = pathlib.Path(conf["app_path"])
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes()) if app.is_dir() else {}
        print("Host app exists:", app.is_dir(), "correct bundle:", info.get("CFBundleIdentifier") == "com.ioant.clip.macos", "daily target:", info.get("ClipCloudKitContainer") is None, flush=True)
    except (OSError, ValueError, KeyError, TypeError):
        print("Host app configuration invalid", flush=True)
else: print("Host configuration missing", flush=True)
print("Read-only diagnosis complete; no Chrome profile modification or capture", flush=True)
