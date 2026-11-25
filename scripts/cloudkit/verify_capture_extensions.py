import pathlib, plistlib, subprocess, sys
platform, raw = sys.argv[1:]
app = pathlib.Path(raw)
mac = platform == "macOS"
base = app/"Contents" if mac else app
def entitlements(path):
    subprocess.run(["/usr/bin/codesign","--verify","--strict",str(path)],check=True)
    p = subprocess.run(["/usr/bin/codesign","-d","--entitlements",":-",str(path)],capture_output=True,check=True)
    return plistlib.loads(p.stdout)
assert entitlements(app)["com.apple.security.application-groups"] == ["group.com.ioant.clip"]
expected = {"com.ioant.clip."+("macos" if mac else "ios")+".safari":"com.apple.Safari.web-extension"}
if not mac: expected["com.ioant.clip.ios.share"]="com.apple.share-services"
seen = set()
for extension in (base/"PlugIns").glob("*.appex"):
    extbase = extension/"Contents" if mac else extension
    info = plistlib.loads((extbase/"Info.plist").read_bytes())
    bundle = info["CFBundleIdentifier"]
    assert bundle in expected
    assert info["NSExtension"]["NSExtensionPointIdentifier"] == expected[bundle]
    ent = entitlements(extension)
    assert ent["com.apple.security.application-groups"] == ["group.com.ioant.clip"]
    assert "com.apple.developer.icloud-services" not in ent
    if bundle.endswith(".safari"):
        resources = extbase/"Resources" if mac else extbase
        assert (resources/"manifest.json").is_file() and (resources/"Popup/popup.html").is_file() and (resources/"CaptureEngine/injected.js").is_file()
    seen.add(bundle)
    print("Verified signed extension:",bundle)
assert seen == set(expected)
print("PASS: containing app and all expected extensions share the registered group")
