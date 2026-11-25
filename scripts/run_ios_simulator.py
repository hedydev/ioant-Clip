#!/usr/bin/env python3
"""Launch one dedicated development simulator for interactive user review."""
import json, os, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = pathlib.Path("/Volumes/LunaDrive/DeveloperCache")
derived = CACHE / "projects/ioant-clip/DerivedData" if CACHE.is_dir() and os.access(CACHE,os.W_OK) else ROOT / "DerivedData"
app = derived / "iOS/Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
if not app.is_dir():
    raise SystemExit("Previously built iOS app not found: " + str(app))
import plistlib
with (app / "Info.plist").open("rb") as f:
    bundle = plistlib.load(f)["CFBundleIdentifier"]
if bundle != "com.ioant.clip.ios":
    raise SystemExit("Unexpected bundle identifier: " + bundle)
def run(*args, timeout=30):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=timeout).strip()
def sim(*args, timeout=30):
    return run("/usr/bin/xcrun","simctl",*args,timeout=timeout)
inventory=json.loads(sim("list","-j"))
name="ioant-Clip Review iPhone"
legacy_name="ioant-Note Review iPhone"
runtimes=[r for r in inventory["runtimes"] if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
if not runtimes: raise SystemExit("No available iOS simulator runtime")
runtimes.sort(key=lambda r:tuple(int(x) for x in r["version"].split(".")),reverse=True)
existing=[d for r in runtimes for d in inventory["devices"].get(r["identifier"],[]) if d.get("isAvailable") and d["name"] in (name,legacy_name)]
if len(existing)>1: raise SystemExit("Multiple dedicated review devices; refusing ambiguous selection")
if existing:
    device=existing[0]; udid=device["udid"]; already_booted=device["state"]=="Booted"
else:
    runtime=runtimes[0]
    supported=runtime.get("supportedDeviceTypes") or inventory["devicetypes"]
    phones=[d for d in supported if d.get("name","").startswith("iPhone")]
    if not phones: raise SystemExit("No compatible iPhone device type")
    kind=next((d for d in phones if d["name"]=="iPhone 17 Pro"),phones[0])
    udid=sim("create",name,kind["identifier"],runtime["identifier"])
    already_booted=False
print("Dedicated simulator:",name,"UDID:",udid,"previously booted:",already_booted,flush=True)
boot_requested=False
app_launched=False
try:
    if not already_booted:
        boot_requested=True
        sim("boot",udid,timeout=60)
    sim("bootstatus",udid,"-b",timeout=120)
    sim("install",udid,str(app),timeout=60)
    print(sim("launch",udid,bundle,timeout=45),flush=True)
    app_launched=True
    developer=pathlib.Path(run("/usr/bin/xcode-select","-p"))
    simulator=developer / "Applications/Simulator.app"
    if not simulator.is_dir():
        raise RuntimeError("Simulator application missing: " + str(simulator))
    try:
        run("/usr/bin/open","-a",str(simulator),"--args","-CurrentDeviceUDID",udid,timeout=20)
        print("Simulator UI open request succeeded (window visibility not independently verified).",flush=True)
    except subprocess.CalledProcessError as e:
        print("Simulator open with arguments failed:",e.output,flush=True)
        run("/usr/bin/open","-a",str(simulator),timeout=20)
        print("Simulator opened without arguments. Select the dedicated device in File > Open Simulator if needed.",flush=True)
    print("Interactive review device intentionally left booted; no other devices changed.",flush=True)
except BaseException:
    if boot_requested and not app_launched:
        try: sim("shutdown",udid,timeout=30)
        except Exception as e: print("Review device cleanup failed:",e,file=sys.stderr)
    if app_launched: print('Client launched; dedicated simulator retained for interactive review despite UI error.',flush=True)
    raise
