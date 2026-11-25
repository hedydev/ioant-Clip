import pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / "Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "com.ioant.clip.ios.simsmoke"
assert info["ClipCloudKitContainer"] == "iCloud.com.ioant.clip"
assert info["ClipCloudKitEnvironment"] == "Development"
assert info["ClipCloudKitSmoke"] == "YES"
subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(app)], check=True)
ent = plistlib.loads(subprocess.check_output(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(app)], stderr=subprocess.DEVNULL))
assert ent.get("com.apple.developer.icloud-container-identifiers") == ["iCloud.com.ioant.clip"]
assert "CloudKit" in ent.get("com.apple.developer.icloud-services", [])
assert ent.get("com.apple.developer.icloud-container-environment") == "Development"
print("PASS: simulator smoke identity and ad hoc CloudKit Development entitlements verified; server authorization not yet verified")
