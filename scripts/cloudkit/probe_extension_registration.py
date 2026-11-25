#!/usr/bin/env python3
"""Read only the registered ioant-Clip plugins and daily synchronization metadata."""
import os, pathlib, subprocess, json, plistlib, hashlib
root=pathlib.Path(__file__).resolve().parents[2]
cache=pathlib.Path("/Volumes/LunaDrive/DeveloperCache")
base=cache/"projects/ioant-clip/DerivedData" if cache.is_dir() and os.access(cache,os.W_OK) else root/"DerivedData"
mac=base/"CloudKitCaptureExtensions/macOS/Build/Products/Debug/ioant-Clip-macOS.app"
ios=base/"CloudKitCaptureExtensions/SimulatorPageLayout/Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
udid="614FDA13-6198-452B-A6B2-94AA5591B30A"
def run(*args):
    return subprocess.run(args,text=True,capture_output=True,timeout=30,check=True).stdout.strip()
def sim(*args): return run("/usr/bin/xcrun","simctl",*args)
def digest(app):
    info=plistlib.loads((app/"Info.plist").read_bytes())
    return hashlib.sha256((app/info["CFBundleExecutable"]).read_bytes()).digest()
# Apple's troubleshooting documentation recommends pluginkit. Filter strictly to our own ID.
registered=run("/usr/bin/pluginkit","-mAvvv","-i","com.ioant.clip.macos.safari")
expected=next((mac/"Contents/PlugIns").glob("*.appex"))
print("Mac Safari plugin registry:",registered or "(no result)",flush=True)
print("Current signed Safari bundle registered:",str(expected) in registered,flush=True)
installed=pathlib.Path(sim("get_app_container",udid,"com.ioant.clip.ios","app"))
assert digest(installed)==digest(ios),"unexpected simulator binary"
for ext in sorted((installed/"PlugIns").glob("*.appex")):
    print("Installed iOS extension:",plistlib.loads((ext/"Info.plist").read_bytes())["CFBundleIdentifier"],flush=True)
data=pathlib.Path(sim("get_app_container",udid,"com.ioant.clip.ios","data"))
def group_snapshot(directory):
    try:
        return read_group_snapshot(directory)
    except PermissionError:
        return {"available": False, "reason": "permission_denied"}

def read_group_snapshot(directory):
    if not directory.is_dir(): return {"exists":False}
    results={"exists":True}
    for source in ("safari","share"):
        path=directory/("extension-"+source+"-contact.json")
        if path.is_file() and not path.is_symlink() and path.stat().st_size<=512:
            try:
                item=json.loads(path.read_bytes())
                if item.get("source")==source and item.get("version")==1 and item.get("activity") in ("queued","ping"):
                    results[source]=item["activity"]
            except (ValueError,KeyError): pass
    inbox=directory/"CaptureInbox"
    results["pending_count"]=sum(1 for f in inbox.glob("*.json") if f.is_file() and not f.is_symlink())
    return results
print("Mac App Group evidence:",group_snapshot(pathlib.Path.home()/"Library/Group Containers/group.com.ioant.clip"),flush=True)
try:
    group=pathlib.Path(sim("get_app_container",udid,"com.ioant.clip.ios","group.com.ioant.clip"))
    print("iOS App Group evidence:",group_snapshot(group),flush=True)
except subprocess.CalledProcessError:
    print("iOS App Group container not resolved by simctl",flush=True)
daily="Library/Application Support/ioant-Note/notes.json"
a=json.loads((pathlib.Path.home()/daily).read_bytes())
b=json.loads((data/daily).read_bytes())
notes=lambda x:{n["id"]:n for n in x["notes"]}
print("Daily Mac/iOS note counts:",len(notes(a)),len(notes(b)),flush=True)
print("Daily note identities equal:",set(notes(a))==set(notes(b)),flush=True)
print("Daily note contents equal:",notes(a)==notes(b),flush=True)
x,y=a.get("syncEnrollment"),b.get("syncEnrollment")
print("Daily sync binding equal:",bool(x and y and x.get("account")==y.get("account")),flush=True)
print("Paused states:",(x or {}).get("isPaused"),(y or {}).get("isPaused"),flush=True)
print("No captures inserted, no settings or accounts changed",flush=True)
