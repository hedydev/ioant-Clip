#!/usr/bin/env python3
"""Install only over our prior completed synthetic test and open the real review UI."""
import json, os, pathlib, plistlib, subprocess, hashlib, time
root = pathlib.Path(__file__).resolve().parents[2]
cache = pathlib.Path("/Volumes/LunaDrive/DeveloperCache")
derived = (cache / "projects/ioant-clip/DerivedData" if cache.is_dir() and os.access(cache, os.W_OK) else root / "DerivedData") / "CloudKitSmoke"
app = derived / "SimulatorUIReviewScene/Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
previous = derived / "SimulatorUIReview/Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
bundle = "com.ioant.clip.ios"
udid = "614FDA13-6198-452B-A6B2-94AA5591B30A"
def sim(*args, timeout=30, check=True):
    return subprocess.run(["/usr/bin/xcrun", "simctl", *args], capture_output=True, text=True, timeout=timeout, check=check)
def info(path):
    return plistlib.loads((path / "Info.plist").read_bytes())
def binary_digest(path):
    return hashlib.sha256((path / info(path)["CFBundleExecutable"]).read_bytes()).digest()
subprocess.run(["/usr/bin/python3", str(root / "scripts/cloudkit/verify_simulator_smoke.py"), str(app), bundle, "ui"], check=True)
devices = json.loads(sim("list", "-j", "devices", "booted").stdout)["devices"]
assert any(d["udid"] == udid and d["state"] == "Booted" for ds in devices.values() for d in ds), "original simulator not booted"
installed = pathlib.Path(sim("get_app_container", udid, bundle, "app").stdout.strip())
data = pathlib.Path(sim("get_app_container", udid, bundle, "data").stdout.strip())
old_info = info(installed)
assert old_info.get("ClipCloudKitSmoke") == "NO" and old_info.get("ClipCloudKitUIReview") == "YES" and old_info.get("CFBundleIdentifier") == bundle, "refuse to replace normal app"
assert binary_digest(installed) == binary_digest(previous), "installed review differs from last verified owned build"
receipts = {}
for name in ("cloudkit-smoke-result.txt", "cloudkit-conflict-result.txt", "cloudkit-resolution-result.txt"):
    payload = (data / "Documents" / name).read_bytes()
    assert b"RESULT: PASS\n" in payload, "missing prior successful synthetic receipt"
    receipts[name] = payload
ui_dir = pathlib.Path("Library/Application Support/ioant-Clip-CloudKit-UI-Review")
assert not (data / ui_dir).exists(), "UI review data already exists; review before launch"
jobs = sim("spawn", udid, "launchctl", "list").stdout
assert not any(bundle in line and line.split()[0].isdigit() for line in jobs.splitlines()), "app already running; do not terminate"
sim("install", udid, str(app), timeout=60)
installed = pathlib.Path(sim("get_app_container", udid, bundle, "app").stdout.strip())
data = pathlib.Path(sim("get_app_container", udid, bundle, "data").stdout.strip())
assert binary_digest(installed) == binary_digest(app)
assert info(installed).get("ClipCloudKitUIReview") == "YES"
assert info(installed).get("ClipCloudKitSmoke") == "NO"
assert all((data / "Documents" / name).read_bytes() == payload for name, payload in receipts.items()), "prior smoke evidence changed"
assert not (data / ui_dir).exists(), "unexpected UI review library"
print("Only owned test app updated; all three previous receipts preserved", flush=True)
# Open the ordinary app in the isolated UI lane. No auto-enrollment.
launched = False
try:
    result = sim("launch", udid, bundle, timeout=45)
    launched = True
    print(result.stdout.strip(), flush=True)
    for _ in range(15):
        data = pathlib.Path(sim("get_app_container", udid, bundle, "data").stdout.strip())
        if (data / ui_dir / "notes.json").is_file(): break
        time.sleep(1)
    jobs = sim("spawn", udid, "launchctl", "list").stdout
    assert any(bundle in line and line.split()[0].isdigit() for line in jobs.splitlines()), "UI process not running"
    notes = data / ui_dir / "notes.json"
    assert notes.is_file(), "isolated UI library not initialized after bounded wait"
    local = json.loads(notes.read_text())
    assert not local.get("notes") and local.get("syncEnrollment") is None, "unexpected initial library or enrollment"
    print("PASS: real iPhone UI process running, isolated empty local library and no enrollment; left open for interactive review", flush=True)
    print("No other simulator or daily application data touched.", flush=True)

except BaseException:
    if launched:
        print("Owned UI launch cleanup exit:", sim("terminate", udid, bundle, check=False).returncode, flush=True)
    raise
