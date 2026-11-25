#!/usr/bin/env python3
"""Upgrade only the known development simulator without reinstall/uninstall or rebinding."""
import json, os, pathlib, plistlib, subprocess, hashlib, time, uuid
root = pathlib.Path(__file__).resolve().parents[2]
cache = pathlib.Path("/Volumes/LunaDrive/DeveloperCache")
base = cache / "projects/ioant-clip/DerivedData" if cache.is_dir() and os.access(cache, os.W_OK) else root / "DerivedData"
app = base / "CloudKitCaptureExtensions/Simulator/Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
prior = base / "CloudKitSmoke/SimulatorDevelopment/Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
bundle = "com.ioant.clip.ios"
udid = "614FDA13-6198-452B-A6B2-94AA5591B30A"
support = pathlib.Path("Library/Application Support")
daily = support / "ioant-Note"
review = support / "ioant-Clip-CloudKit-UI-Review"
def sim(*args, timeout=30, check=True):
    return subprocess.run(["/usr/bin/xcrun","simctl",*args], capture_output=True,text=True,timeout=timeout,check=check)
def info(path): return plistlib.loads((path/"Info.plist").read_bytes())
def digest(path): return hashlib.sha256((path/info(path)["CFBundleExecutable"]).read_bytes()).digest()
def container(kind): return pathlib.Path(sim("get_app_container",udid,bundle,kind).stdout.strip())
def active(): return any(bundle in line and line.split()[0].isdigit() for line in sim("spawn",udid,"launchctl","list").stdout.splitlines())
def snapshot(data):
    paths = [daily/"notes.json",daily/"cloudkit-remote-checkpoint-v1.json",review/"notes.json",review/"cloudkit-remote-checkpoint-v1.json"]
    paths += [pathlib.Path("Documents")/name for name in ("cloudkit-smoke-result.txt","cloudkit-conflict-result.txt","cloudkit-resolution-result.txt")]
    return {p:(data/p).read_bytes() for p in paths if (data/p).is_file()}
def ids(library): return {note["id"] for note in library["notes"]}
subprocess.run(["/usr/bin/python3",str(root/"scripts/cloudkit/verify_simulator_smoke.py"),str(app),bundle,"development"],check=True)
subprocess.run(["/usr/bin/python3",str(root/"scripts/cloudkit/verify_capture_extensions.py"),"simulator",str(app)],check=True)
devices=json.loads(sim("list","-j","devices","booted").stdout)["devices"]
assert any(d["udid"]==udid and d["state"]=="Booted" for ds in devices.values() for d in ds)
installed=container("app")
assert info(installed).get("ClipCloudKitDevelopment")=="YES"
assert digest(installed)==digest(prior), "unexpected installed binary, no replacement"
if active():
    sim("terminate",udid,bundle)
    assert not active(), "prior process did not stop"
data=container("data")
saved=snapshot(data)
assert daily/"notes.json" in saved
before=json.loads(saved[daily/"notes.json"])
assert isinstance(before["notes"],list)
backup=data/daily/"DevelopmentBackups"/(str(uuid.uuid4())+".json")
backup.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
fd=os.open(backup,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
with os.fdopen(fd,"wb") as stream: stream.write(saved[daily/"notes.json"])
assert backup.read_bytes()==saved[daily/"notes.json"]
print("Verified simulator backup; notes:",len(ids(before)),"enrolled:",before.get("syncEnrollment") is not None,flush=True)
sim("install",udid,str(app),timeout=60)
installed=container("app")
data=container("data")
assert digest(installed)==digest(app)
assert snapshot(data)==saved, "prior app data changed during upgrade"
assert len(list((installed/"PlugIns").glob("*.appex")))==2
print("PASS: in-place upgrade preserved prior daily data, checkpoint and review receipts",flush=True)
result=sim("launch",udid,bundle,timeout=45)
print(result.stdout.strip(),flush=True)
assert active()
current=json.loads((container("data")/daily/"notes.json").read_bytes())
assert current.get("syncEnrollment")==before.get("syncEnrollment"), "existing binding changed"
assert ids(before).issubset(ids(current)), "prior note identities missing"
mac=json.loads((pathlib.Path.home()/support/daily.name/"notes.json").read_bytes())
print("Mac notes:",len(ids(mac)),"iOS notes:",len(ids(current)),"matching IDs:",len(ids(mac)&ids(current)),flush=True)
print("PASS: extension-enabled daily iOS process running; enrollment retained; no test capture inserted",flush=True)
