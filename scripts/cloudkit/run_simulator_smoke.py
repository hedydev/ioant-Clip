#!/usr/bin/env python3
import json, os, pathlib, subprocess, time, sys
root = pathlib.Path(__file__).resolve().parents[2]
cache = pathlib.Path("/Volumes/LunaDrive/DeveloperCache")
derived = (cache / "projects/ioant-clip/DerivedData" if cache.is_dir() and os.access(cache, os.W_OK) else root / "DerivedData") / ("CloudKitSmoke/SimulatorRegistered" if len(sys.argv) == 2 and sys.argv[1] == "--registered" else "CloudKitSmoke/Simulator")
app = derived / "Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
assert sys.argv[1:] in ([], ["--registered"])
bundle = "com.ioant.clip.ios" if sys.argv[1:] else "com.ioant.clip.ios.simsmoke"
def sim(*args, timeout=30, check=True):
    return subprocess.run(["/usr/bin/xcrun", "simctl", *args], capture_output=True, text=True, timeout=timeout, check=check)
subprocess.run(["/usr/bin/python3", str(root / "scripts/cloudkit/verify_simulator_smoke.py"), str(app), bundle], check=True)
devices = json.loads(sim("list", "-j", "devices", "booted").stdout)["devices"]
phones = [d for ds in devices.values() for d in ds if d["state"] == "Booted" and d.get("isAvailable") and d["name"].startswith("iPhone")]
for d in phones: print("Booted iPhone:", d["name"], d["udid"], flush=True)
if len(phones) != 1:
    raise SystemExit("BLOCKED: exactly one booted iPhone is required; no device changed")
udid = phones[0]["udid"]
# Never replace an existing test installation or any normal Clip app.
if sim("get_app_container", udid, bundle, "app", check=False).returncode == 0:
    raise SystemExit("BLOCKED: target bundle already installed; no app replaced; explicit review needed")
launched = False
try:
    sim("install", udid, str(app), timeout=60)
    print("Installed isolated simulator smoke on", udid, flush=True)
    launch = sim("launch", udid, bundle, "--clip-simulator-smoke", timeout=45)
    launched = True
    print(launch.stdout.strip(), flush=True)
    data = pathlib.Path(sim("get_app_container", udid, bundle, "data").stdout.strip())
    result = data / "Documents/cloudkit-smoke-result.txt"
    last = ""
    for _ in range(90):
        if result.is_file():
            latest = result.read_text()
            if latest != last:
                print(latest, flush=True)
                last = latest
            if "RESULT: PASS\n" in latest: break
            if "RESULT: FAIL" in latest or "RESULT: BLOCKED" in latest: raise SystemExit(1)
        time.sleep(2)
    else: raise SystemExit("BLOCKED: result timeout; do not repeat uncertain cloud writes")
finally:
    if launched:
        stopped = sim("terminate", udid, bundle, check=False)
        print("Owned test app terminate exit:", stopped.returncode, flush=True)
    print("No simulator boot, shutdown, erase or daily app change. Test installation retained.", flush=True)
