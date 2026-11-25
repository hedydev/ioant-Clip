import pathlib, os, stat, json, subprocess, time, uuid
home=pathlib.Path.home()
root=home/"Library/Group Containers/group.com.ioant.clip"
legacy=home/"Library/Application Support/ioant-Note"
library=json.loads((legacy/"notes.json").read_bytes())
ids={x["id"].lower() for x in library["notes"]}
print("Existing notes:",len(ids),"enrolled:",bool(library.get("syncEnrollment")),flush=True)
for name,path in [("legacy",legacy/"CaptureInbox"),("group",root),("shared",root/"CaptureInbox")]:
    try:
        st=path.lstat()
        print(name,"directory",stat.S_ISDIR(st.st_mode),"uid",st.st_uid,"mode",oct(stat.S_IMODE(st.st_mode)),flush=True)
        if name=="group": continue
        for item in path.iterdir():
            if item.suffix!=".json": continue
            try: ident=str(uuid.UUID(item.stem))
            except ValueError: continue
            try:
                st=item.lstat()
                if not stat.S_ISREG(st.st_mode): continue
                valid=False
                if st.st_size<=32*1024*1024:
                    value=json.loads(item.read_bytes())
                    valid=isinstance(value,dict) and value.get("version")==1 and all(isinstance(value.get(k),str) for k in ("title","sourceURL","html","text","mode"))
                print(name,"pending",ident,"bytes",st.st_size,"mode",oct(stat.S_IMODE(st.st_mode)),"uid",st.st_uid,"valid envelope",valid,"already imported",ident.lower() in ids,flush=True)
            except (OSError,ValueError) as e: print(name,"file error",type(e).__name__,getattr(e,"errno",None),flush=True)
    except OSError as e: print(name,"directory error",type(e).__name__,e.errno,flush=True)
for source in ("safari","share"):
    path=root/("extension-"+source+"-contact.json")
    try:
        v=json.loads(path.read_bytes())
        print(source,"receipt",v.get("activity"),"age seconds",round(time.time()-v.get("unixSeconds",0)),flush=True)
    except (ValueError,OSError,TypeError): print(source,"receipt absent/unreadable",flush=True)
# Filter OS logs strictly to this app and sandbox denials. Never print page content.
p=subprocess.run(["/usr/bin/log","show","--last","15m","--style","compact","--predicate",'(process == "sandboxd" OR subsystem == "com.apple.sandbox") AND (eventMessage CONTAINS[c] "ioant-Clip" OR eventMessage CONTAINS[c] "group.com.ioant.clip")'],capture_output=True,text=True,timeout=30)
for line in p.stdout.splitlines()[-25:]:
    if "deny" in line.lower():
        print("Sandbox denial:",line[:500],flush=True)
print("Read-only inspection complete; no captures changed.",flush=True)

import plistlib
app=pathlib.Path("/Volumes/LunaDrive/DeveloperCache/projects/ioant-clip/DerivedData/CloudKitCaptureExtensions/macOS/Build/Products/Debug/ioant-Clip-macOS.app")
for bundle in [app,*((app/"Contents/PlugIns").glob("*.appex"))]:
    profile=bundle/"Contents/embedded.provisionprofile"
    if not profile.is_file():
        print(bundle.name,"embedded profile missing"); continue
    p=plistlib.loads(subprocess.check_output(["/usr/bin/security","cms","-D","-i",str(profile)]))
    print(bundle.name,"profile group permissions",p.get("Entitlements",{}).get("com.apple.security.application-groups"),flush=True)
    e=subprocess.check_output(["/usr/bin/codesign","-d","--entitlements",":-",str(bundle)],stderr=subprocess.DEVNULL)
    print(bundle.name,"signed group permissions",plistlib.loads(e).get("com.apple.security.application-groups"),flush=True)

# Scan only relevant locally cached profiles; never change/revoke profiles.
import datetime
from profile_inventory import parse_profile, matching_profile
count=0
for folder in (home/"Library/Developer/Xcode/UserData/Provisioning Profiles",home/"Library/MobileDevice/Provisioning Profiles"):
    if not folder.is_dir(): continue
    for item in folder.iterdir():
        if item.suffix not in (".provisionprofile",".mobileprovision") or not item.is_file(): continue
        try:
            p=parse_profile(item)
            if not p: continue
            match=matching_profile(p,"macOS",datetime.datetime.now(datetime.timezone.utc))
            if not match or match[0]!="64RS366WKG" or "iCloud.com.ioant.clip" not in match[1]: continue
            authorized="group.com.ioant.clip" in p.get("Entitlements",{}).get("com.apple.security.application-groups",[])
            print("Cached Mac main profile group authorized:",authorized,flush=True)
            if authorized: count+=1
        except Exception: pass
print("Eligible cached Mac main profiles with both CloudKit and App Group:",count,flush=True)
