import pathlib, plistlib, subprocess, sys, json, os, time
root = pathlib.Path(__file__).resolve().parents[2]
cache = pathlib.Path("/Volumes/LunaDrive/DeveloperCache")
derived = (cache / "projects/ioant-clip/DerivedData" if cache.is_dir() and os.access(cache, os.W_OK) else root / "DerivedData") / "CloudKitSmoke/SimulatorRegistered"
app = derived / "Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
bundle = "com.ioant.clip.ios"
udid = "614FDA13-6198-452B-A6B2-94AA5591B30A"
mode = sys.argv[1]
assert mode in ("conflict", "verify-resolution")
result_name = "cloudkit-conflict-result.txt" if mode == "conflict" else "cloudkit-resolution-result.txt"
def sim(*args, timeout=30, check=True):
    return subprocess.run(["/usr/bin/xcrun", "simctl", *args], capture_output=True, text=True, timeout=timeout, check=check)
devices = json.loads(sim("list", "-j", "devices", "booted").stdout)["devices"]
assert any(d["udid"] == udid and d["state"] == "Booted" for ds in devices.values() for d in ds), "original user simulator not booted"
installed = pathlib.Path(sim("get_app_container", udid, bundle, "app").stdout.strip())
data = pathlib.Path(sim("get_app_container", udid, bundle, "data").stdout.strip())
info = plistlib.loads((installed / "Info.plist").read_bytes())
assert info.get("ClipCloudKitSmoke") == "YES" and info.get("CFBundleIdentifier") == bundle, "refuse to touch normal app"
assert info.get("ClipCloudKitContainer") == "iCloud.com.ioant.clip" and info.get("ClipCloudKitEnvironment") == "Development"
prior = data / "Documents/cloudkit-smoke-result.txt"
assert prior.is_file() and "RESULT: PASS\n" in prior.read_text(), "prior smoke receipt missing"
assert not (data / "Documents" / result_name).exists(), "existing stage receipt; reconcile instead of replay"
if mode == "verify-resolution":
    assert "RESULT: PASS\n" in (data / "Documents/cloudkit-conflict-result.txt").read_text()
subprocess.run(["/usr/bin/python3", str(root / "scripts/cloudkit/verify_simulator_smoke.py"), str(app), bundle], check=True)
# Do not terminate a user-running application. Previous smoke was terminated.
if mode == "conflict":
    # Check exact owned smoke process is absent before installing the update.
    jobs = sim("spawn", udid, "launchctl", "list").stdout
    assert not any(bundle in line and line.split()[0].isdigit() for line in jobs.splitlines()), "smoke still running"
    sim("install", udid, str(app), timeout=60)
    print("Updated previously verified smoke app only, preserving container", flush=True)
    assert pathlib.Path(sim("get_app_container", udid, bundle, "data").stdout.strip()) == data
else:
    assert (installed / info["CFBundleExecutable"]).read_bytes() == (app / info["CFBundleExecutable"]).read_bytes(), "unexpected installed build"
launched = False
try:
    print(sim("launch", udid, bundle, "--clip-simulator-" + mode, timeout=45).stdout.strip(), flush=True)
    launched = True
    result = data / "Documents" / result_name
    for _ in range(90):
        if result.is_file():
            text = result.read_text()
            if "RESULT: PASS\n" in text:
                print(text, flush=True); break
            if "RESULT: FAIL" in text or "RESULT: BLOCKED" in text:
                print(text, flush=True); raise SystemExit(1)
        time.sleep(2)
    else: raise SystemExit("Timed out; reconcile exact cloud records before any retry")
finally:
    if launched:
        print("Owned smoke terminate exit:", sim("terminate", udid, bundle, check=False).returncode, flush=True)
    print("Original simulator left booted; test data retained.", flush=True)
