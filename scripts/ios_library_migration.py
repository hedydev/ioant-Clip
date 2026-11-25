"""Non-destructive one-time copy for an explicitly selected simulator.

The old app and its data are retained. Never merge or overwrite two libraries.
Physical devices cannot access another app's sandbox; use a separate export
workflow if needed. This module is only used by local review launch scripts.
"""
import json
import os
import pathlib
import plistlib
import shutil
import tempfile
import subprocess

LEGACY_ID = "com.ioant.note.ios"
CURRENT_ID = "com.ioant.clip.ios"
RELATIVE_LIBRARY = pathlib.Path("Library/Application Support/ioant-Note/notes.json")

def copy_if_absent(source, destination):
    if not source.exists():
        return "no legacy library"
    if source.is_symlink() or not source.is_file():
        raise RuntimeError("Legacy library is not a regular file")
    if destination.exists() or destination.is_symlink():
        return "destination exists; kept both libraries unchanged"
    # Check basic shape without logging contents or rewriting JSON.
    with source.open("rb") as handle:
        value = json.load(handle)
    if not isinstance(value, dict) or not isinstance(value.get("notes"), list):
        raise RuntimeError("Legacy library is not a recognized notes.json")
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix=".clip-migration-", dir=destination.parent)
    try:
        with os.fdopen(fd, "wb") as handle, source.open("rb") as src:
            shutil.copyfileobj(src, handle)
            handle.flush()
            os.fsync(handle.fileno())
        # Atomic create, never replace a new library from another process.
        try:
            os.link(temporary, destination)
        except FileExistsError:
            return "destination exists; kept both libraries unchanged"
        return "copied legacy library; original retained"
    finally:
        os.unlink(temporary)

def migrate_simulator(udid, sim):
    # Verify the existing old bundle via the device's installed app inventory,
    # not by guessing its container UUID.
    apps = sim("listapps", udid)
    converted = subprocess.run(["/usr/bin/plutil", "-convert", "xml1", "-o", "-", "--", "-"],
                               input=apps.encode(), capture_output=True, check=True, timeout=10)
    installed = plistlib.loads(converted.stdout)
    if LEGACY_ID not in installed:
        print("Migration: no legacy app installed", flush=True)
        return
    source = pathlib.Path(sim("get_app_container", udid, LEGACY_ID, "data")) / RELATIVE_LIBRARY
    destination = pathlib.Path(sim("get_app_container", udid, CURRENT_ID, "data")) / RELATIVE_LIBRARY
    if destination.exists() or destination.is_symlink() or not source.exists():
        print("Migration:", copy_if_absent(source, destination), flush=True)
        return
    # Only stop the old Clip/Note instance on the explicitly selected device.
    # A not-running app is harmless; all other errors block migration.
    try:
        sim("terminate", udid, LEGACY_ID)
    except (RuntimeError, subprocess.CalledProcessError) as e:
        detail = (str(e) + " " + str(getattr(e, "output", ""))).lower()
        if "not running" not in detail and "found nothing to terminate" not in detail:
            raise
    print("Migration:", copy_if_absent(source, destination), flush=True)
