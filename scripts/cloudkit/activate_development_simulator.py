#!/usr/bin/env python3
"""Switch only the exact owned iOS review build to the shared daily development lane.
Do not copy test enrollment, checkpoint, or records into the daily library."""
import json, os, pathlib, plistlib, subprocess, hashlib, time, uuid
root = pathlib.Path(__file__).resolve().parents[2]
cache = pathlib.Path("/Volumes/LunaDrive/DeveloperCache")
base = cache / "projects/ioant-clip/DerivedData" if cache.is_dir() and os.access(cache, os.W_OK) else root / "DerivedData"
app = base / "CloudKitSmoke/SimulatorDevelopment/Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
previous = base / "CloudKitSmoke/SimulatorUIReviewScene/Build/Products/Debug-iphonesimulator/ioant-Clip-iOS.app"
bundle = "com.ioant.clip.ios"
udid = "614FDA13-6198-452B-A6B2-94AA5591B30A"
support = pathlib.Path("Library/Application Support")
review = support / "ioant-Clip-CloudKit-UI-Review"
daily = support / "ioant-Note"
def sim(*args, timeout=30, check=True):
    return subprocess.run(["/usr/bin/xcrun","simctl",*args], capture_output=True,text=True,timeout=timeout,check=check)
def meta(path):
    return plistlib.loads((path/"Info.plist").read_bytes())
def digest(path):
    return hashlib.sha256((path/meta(path)["CFBundleExecutable"]).read_bytes()).digest()
def library(path):
    if not path.is_file(): return None
    value = json.loads(path.read_bytes())
    assert isinstance(value.get("notes"), list), "invalid library"
    return value
def account(value):
    return (value or {}).get("syncEnrollment",{}).get("account") if (value or {}).get("syncEnrollment") else None
def ids(value):
    return {n["id"] for n in (value or {}).get("notes",[])}
def summary(label, value):
    print(label, "notes:", len(ids(value)), "enrolled:", account(value) is not None,
          "paused:", bool((value or {}).get("syncEnrollment",{}).get("isPaused")) if account(value) else False, flush=True)
def container(kind):
    return pathlib.Path(sim("get_app_container",udid,bundle,kind).stdout.strip())
def active():
    return any(bundle in line and line.split()[0].isdigit() for line in sim("spawn",udid,"launchctl","list").stdout.splitlines())
def state(data):
    return {str(p): (data/p).read_bytes() for p in (
        review/"notes.json", review/"cloudkit-remote-checkpoint-v1.json",
        pathlib.Path("Documents/cloudkit-smoke-result.txt"),
        pathlib.Path("Documents/cloudkit-conflict-result.txt"),
        pathlib.Path("Documents/cloudkit-resolution-result.txt")
    ) if (data/p).is_file()}
subprocess.run(["/usr/bin/python3",str(root/"scripts/cloudkit/verify_simulator_smoke.py"),str(app),bundle,"development"],check=True)
devices = json.loads(sim("list","-j","devices","booted").stdout)["devices"]
assert any(d["udid"]==udid and d["state"]=="Booted" for ds in devices.values() for d in ds), "original simulator not booted"
installed=container("app")
assert meta(installed).get("ClipCloudKitUIReview")=="YES" and meta(installed).get("ClipCloudKitSmoke")=="NO"
assert digest(installed)==digest(previous), "unknown installed app; refusing replacement"
data=container("data")
mac=library(pathlib.Path.home()/support/daily.name/"notes.json")
old_review=library(data/review/"notes.json")
old_daily=library(data/daily/"notes.json")
summary("Mac daily",mac)
summary("iOS isolated UI review",old_review)
summary("iOS prior daily",old_daily)
print("Mac zone: ioantNoteRevisionsV1; installed iOS zone: ioantClipUIReview-9A41E893-7AB6-4E73-BFC7-70DD052EA175",flush=True)
print("Existing Mac/review account equal:",account(mac)==account(old_review) if account(mac) and account(old_review) else "not both bound",flush=True)
# Preserve already enrolled daily data. Do not allow unexpected auto-sync after install.
assert account(old_daily) is None, "iOS daily library already enrolled; reconcile before replacing"
if active():
    sim("terminate",udid,bundle)
    assert not active(), "owned review did not stop"
data=container("data")
old_daily=library(data/daily/"notes.json")
assert account(old_daily) is None
saved=state(data)
assert str(review/"notes.json") in saved, "prior review library missing"
for name in ("cloudkit-smoke-result.txt","cloudkit-conflict-result.txt","cloudkit-resolution-result.txt"):
    assert b"RESULT: PASS\n" in saved["Documents/"+name]
daily_bytes=(data/daily/"notes.json").read_bytes() if old_daily is not None else None
if daily_bytes is not None:
    backup=data/daily/"DevelopmentBackups"/(str(uuid.uuid4())+".json")
    backup.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
    fd=os.open(backup,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,"wb") as stream: stream.write(daily_bytes)
    assert backup.read_bytes()==daily_bytes
sim("install",udid,str(app),timeout=60)
installed=container("app")
data=container("data")
assert digest(installed)==digest(app) and meta(installed)["ClipCloudKitDevelopment"]=="YES"
assert state(data)==saved,"test library or prior receipts changed"
if daily_bytes is not None: assert (data/daily/"notes.json").read_bytes()==daily_bytes
else: assert not (data/daily/"notes.json").exists()
print("PASS: daily development binary installed, isolated review data and all prior receipts retained",flush=True)
launched=False
try:
    result=sim("launch",udid,bundle,timeout=45)
    launched=True
    print(result.stdout.strip(),flush=True)
    for _ in range(15):
        data=container("data")
        if (data/daily/"notes.json").is_file(): break
        time.sleep(1)
    assert active()
    current=library(data/daily/"notes.json")
    assert current is not None and account(current) is None
    assert ids(old_daily).issubset(ids(current)) and state(data)==saved
    summary("iOS daily development",current)
    print("PASS: normal iOS development lane running on same container/environment/zone as Mac; no automatic enrollment",flush=True)
    print("User must connect iCloud in the normal iOS app; no test data copied or uploaded",flush=True)
except BaseException:
    if launched: print("Owned launch cleanup:",sim("terminate",udid,bundle,check=False).returncode,flush=True)
    raise
