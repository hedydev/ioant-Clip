#!/usr/bin/env python3
"""Install Note on the uniquely identified already booted user review device."""
import json, pathlib, subprocess, plistlib, os
root=pathlib.Path(__file__).resolve().parents[1]
cache=pathlib.Path("/Volumes/LunaDrive/DeveloperCache")
derived=cache/"projects/ioant-note/DerivedData" if cache.is_dir() and os.access(cache,os.W_OK) else root/"DerivedData"
app=derived/"iOS/Build/Products/Debug-iphonesimulator/ioant-Note-iOS.app"
with (app/"Info.plist").open("rb") as f:
    assert plistlib.load(f)["CFBundleIdentifier"]=="com.ioant.note.ios"
def sim(*args, timeout=30):
    p=subprocess.run(["/usr/bin/xcrun","simctl",*args],capture_output=True,text=True,timeout=timeout)
    if p.returncode: raise RuntimeError(p.stderr or p.stdout)
    return p.stdout.strip()
inventory=json.loads(sim("list","-j","devices"))
all_devices=[(runtime,d) for runtime,ds in inventory["devices"].items() for d in ds]
for runtime,d in all_devices:
    if d["state"]=="Booted" or d["name"]=="ioant-Note Review iPhone":
        print("Device:",d["name"],runtime,d["udid"],d["state"],flush=True)
targets=[d for runtime,d in all_devices if runtime.endswith(".iOS-27-2") and d["name"]=="iPhone 18 Pro" and d["state"]=="Booted" and d.get("isAvailable",False)]
if len(targets)!=1:
    raise SystemExit("Expected exactly one booted iPhone 18 Pro (iOS 27.2); no device modified.")
udid=targets[0]["udid"]
print("Installing only on visible device",udid,flush=True)
sim("install",udid,str(app),timeout=60)
print("Installed:",sim("get_app_container",udid,"com.ioant.note.ios","app"),flush=True)
print("Launched:",sim("launch",udid,"com.ioant.note.ios",timeout=45),flush=True)
print("No device created, booted, shut down or erased.",flush=True)
