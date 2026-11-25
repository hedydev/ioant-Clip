#!/usr/bin/env python3
"""Read only owned UI-review simulator metadata and synthetic storage paths."""
import json, os, pathlib, plistlib, subprocess, hashlib
root = pathlib.Path(__file__).resolve().parents[2]
cache = pathlib.Path("/Volumes/LunaDrive/DeveloperCache")
derived = (cache / "projects/ioant-clip/DerivedData" if cache.is_dir() and os.access(cache, os.W_OK) else root / "DerivedData") / "CloudKitSmoke"
app = derived / "SimulatorUIReview/Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
bundle = "com.ioant.clip.ios"
udid = "614FDA13-6198-452B-A6B2-94AA5591B30A"
def sim(*args, timeout=30):
    return subprocess.check_output(["/usr/bin/xcrun", "simctl", *args], text=True, timeout=timeout).strip()
def info(path):
    return plistlib.loads((path / "Info.plist").read_bytes())
devices = json.loads(sim("list", "-j", "devices", "booted"))["devices"]
assert any(d["udid"] == udid and d["state"] == "Booted" for ds in devices.values() for d in ds)
installed = pathlib.Path(sim("get_app_container", udid, bundle, "app"))
data = pathlib.Path(sim("get_app_container", udid, bundle, "data"))
meta = info(installed)
assert meta.get("ClipCloudKitUIReview") == "YES" and meta.get("ClipCloudKitSmoke") == "NO"
assert meta.get("CFBundleIdentifier") == bundle
assert (installed / meta["CFBundleExecutable"]).read_bytes() == (app / info(app)["CFBundleExecutable"]).read_bytes()
print("Exact installed UI review binary verified", flush=True)
for name in ("cloudkit-smoke-result.txt", "cloudkit-conflict-result.txt", "cloudkit-resolution-result.txt"):
    assert b"RESULT: PASS\n" in (data / "Documents" / name).read_bytes()
print("Three prior synthetic receipts intact", flush=True)
print("Data container UUID:", data.name, flush=True)
print("Scene manifest present:", "UIApplicationSceneManifest" in meta, flush=True)
print("Launch screen present:", "UILaunchScreen" in meta, flush=True)
jobs = sim("spawn", udid, "launchctl", "list")
print("UI review running:", any(bundle in line and line.split()[0].isdigit() for line in jobs.splitlines()), flush=True)
# Inspect ONLY the synthetic review path, not daily or other apps.
for relative in ("Library/Application Support/ioant-Clip-CloudKit-UI-Review", "Documents/ioant-Clip-CloudKit-UI-Review"):
    directory = data / relative
    print(relative, "dir exists:", directory.is_dir(), "notes exists:", (directory / "notes.json").is_file(), flush=True)
    notes = directory / "notes.json"
    if notes.is_file():
        local = json.loads(notes.read_text())
        print("Synthetic library notes:", len(local.get("notes", [])), "journal present:", local.get("syncJournal") is not None, "enrolled:", local.get("syncEnrollment") is not None, flush=True)
print("Read-only inspection finished; no launch or cloud operation", flush=True)
