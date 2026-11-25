#!/usr/bin/env python3
"""Verify the known owned simulator review app; probe local automation capability."""
import json, os, pathlib, plistlib, subprocess, shutil
root = pathlib.Path(__file__).resolve().parents[2]
cache = pathlib.Path("/Volumes/LunaDrive/DeveloperCache")
derived = (cache / "projects/ioant-clip/DerivedData" if cache.is_dir() and os.access(cache, os.W_OK) else root / "DerivedData") / "CloudKitSmoke"
app = derived / "SimulatorUIReviewScene/Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
bundle = "com.ioant.clip.ios"
udid = "614FDA13-6198-452B-A6B2-94AA5591B30A"
def sim(*args):
    return subprocess.check_output(["/usr/bin/xcrun", "simctl", *args], text=True, timeout=30).strip()
devices = json.loads(sim("list", "-j", "devices", "booted"))["devices"]
assert any(d["udid"] == udid and d["state"] == "Booted" for ds in devices.values() for d in ds), "original simulator not booted"
installed = pathlib.Path(sim("get_app_container", udid, bundle, "app"))
meta = plistlib.loads((installed / "Info.plist").read_bytes())
assert meta.get("ClipCloudKitUIReview") == "YES" and meta.get("ClipCloudKitSmoke") == "NO"
assert (installed / meta["CFBundleExecutable"]).read_bytes() == (app / meta["CFBundleExecutable"]).read_bytes()
data = pathlib.Path(sim("get_app_container", udid, bundle, "data"))
notes = data / "Library/Application Support/ioant-Clip-CloudKit-UI-Review/notes.json"
local = json.loads(notes.read_text())
print("Owned iOS review exact binary; note count", len(local.get("notes", [])), "enrolled", local.get("syncEnrollment") is not None, flush=True)
for name in ("cloudkit-smoke-result.txt", "cloudkit-conflict-result.txt", "cloudkit-resolution-result.txt"):
    assert b"RESULT: PASS\n" in (data / "Documents" / name).read_bytes()
print("Prior synthetic receipts intact", flush=True)
jobs = sim("spawn", udid, "launchctl", "list")
print("Review process running:", any(bundle in line and line.split()[0].isdigit() for line in jobs.splitlines()), flush=True)
os.environ["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + os.environ.get("PATH", "")
for name in ("idb", "idb_companion"):
    path = shutil.which(name)
    print(name, "available:" if path else "unavailable", path or "", flush=True)
    if path and name == "idb":
        r = subprocess.run([path, "ui", "describe-all", "--help"], text=True, capture_output=True, timeout=15)
        print("idb describe help exit", r.returncode, (r.stdout + r.stderr)[:3000], flush=True)
