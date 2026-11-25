#!/usr/bin/env python3
"""Install only this project's native messaging host for the current user."""
import argparse
import base64
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
HOST = "com.ioant.note.capture"

def extension_id():
    manifest = json.loads((ROOT / "BrowserExtension/manifest.json").read_text())
    digest = hashlib.sha256(base64.b64decode(manifest["key"], validate=True)).hexdigest()[:32]
    return digest.translate(str.maketrans("0123456789abcdef", "abcdefghijklmnop"))

def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".ioant-note-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(value, handle, indent=2)
            handle.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def install(app, support):
    app = app.resolve(strict=True)
    with (app / "Contents/Info.plist").open("rb") as handle:
        if plistlib.load(handle).get("CFBundleIdentifier") != "com.ioant.note.macos":
            raise ValueError("Not an ioant-Note macOS application.")
    native = support / "ioant-Note/NativeMessaging"
    native.mkdir(parents=True, exist_ok=True, mode=0o700)
    inbox = support / "ioant-Note/CaptureInbox"
    inbox.mkdir(parents=True, exist_ok=True, mode=0o700)
    if inbox.is_symlink() or inbox.stat().st_uid != os.getuid() or inbox.stat().st_mode & 0o077:
        raise ValueError("Unsafe inbox permissions.")
    host = native / "host.py"
    fd, tmp = tempfile.mkstemp(prefix=".host-", dir=native)
    os.close(fd)
    try:
        shutil.copyfile(ROOT / "NativeMessaging/host.py", tmp)
        os.chmod(tmp, 0o700)
        os.replace(tmp, host)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    origins = ["chrome-extension://" + extension_id() + "/"]
    atomic_json(native / "config.json", {"allowed_origins": origins, "app_path": str(app)})
    manifest = {"name": HOST, "description": "ioant-Note local capture", "path": str(host), "type": "stdio", "allowed_origins": origins}
    for browser in ("Google/Chrome", "Microsoft Edge"):
        atomic_json(support / browser / "NativeMessagingHosts" / (HOST + ".json"), manifest)
    return extension_id()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=pathlib.Path)
    args = parser.parse_args()
    os.umask(0o077)
    print("Installed ioant-Note native host; extension ID:", install(args.app, pathlib.Path.home() / "Library/Application Support"))

if __name__ == "__main__":
    main()
