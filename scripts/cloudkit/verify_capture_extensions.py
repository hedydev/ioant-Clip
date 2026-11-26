import pathlib, plistlib, subprocess, sys
platform, raw = sys.argv[1:]
app = pathlib.Path(raw)
mac = platform == "macOS"
base = app/"Contents" if mac else app
def entitlements(path):
    subprocess.run(["/usr/bin/codesign","--verify","--strict",str(path)],check=True)
    p = subprocess.run(["/usr/bin/codesign","-d","--entitlements",":-",str(path)],capture_output=True,check=True)
    if platform == "simulator":
        # The host signature is ad hoc; inspect embedded iOS entitlements.
        # Keep a standalone parser so importing it cannot execute smoke CLI.
        import struct
        info_path = path/"Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        executable = path/info["CFBundleExecutable"]
        raw = executable.read_bytes()
        if raw[:4] != b"\xcf\xfa\xed\xfe":
            import tempfile
            with tempfile.TemporaryDirectory() as temp:
                thin = pathlib.Path(temp)/"arm64"
                subprocess.run(["/usr/bin/lipo",str(executable),"-thin","arm64","-output",str(thin)],check=True)
                raw = thin.read_bytes()
        assert raw[:4] == b"\xcf\xfa\xed\xfe", "expected arm64 simulator"
        ncmds, sizeofcmds = struct.unpack_from("<II", raw, 16)
        pos, limit = 32, 32 + sizeofcmds
        assert limit <= len(raw)
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", raw, pos)
            assert size >= 8 and pos+size <= limit
            if cmd == 0x19:
                nsects = struct.unpack_from("<I",raw,pos+64)[0]
                assert size >= 72+nsects*80
                for i in range(nsects):
                    sec=pos+72+i*80
                    name=raw[sec:sec+16].split(b"\0",1)[0]
                    segment=raw[sec+16:sec+32].split(b"\0",1)[0]
                    if (segment,name)==(b"__TEXT",b"__entitlements"):
                        length,offset=struct.unpack_from("<QI",raw,sec+40)
                        assert length>0 and offset+length<=len(raw)
                        return plistlib.loads(raw[offset:offset+length].rstrip(b"\0"))
            pos+=size
        raise AssertionError("missing simulator entitlements")
    return plistlib.loads(p.stdout)
def profile_group_authorized(bundle):
    if platform == "simulator": return True
    directory = bundle/"Contents" if mac else bundle
    profile = directory/("embedded.provisionprofile" if mac else "embedded.mobileprovision")
    if not profile.is_file(): return False
    result = subprocess.run(["/usr/bin/security","cms","-D","-i",str(profile)],capture_output=True,check=True)
    groups = plistlib.loads(result.stdout).get("Entitlements",{}).get("com.apple.security.application-groups",[])
    return "group.com.ioant.clip" in groups

assert entitlements(app)["com.apple.security.application-groups"] == ["group.com.ioant.clip"]
# A development build with an unauthorized existing main profile can still
# ship the non-modal error hotfix. Report separately; never claim authorization.
main_authorized = profile_group_authorized(app)
print("Main App Group embedded profile authorized:",main_authorized)
if not main_authorized:
    print("WARNING: main app profile lacks group.com.ioant.clip; runtime group access may be denied")
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
    assert profile_group_authorized(extension), "extension profile lacks registered group"
    if bundle.endswith(".safari"):
        resources = extbase/"Resources" if mac else extbase
        assert (resources/"manifest.json").is_file() and (resources/"Popup/popup.html").is_file() and (resources/"CaptureEngine/injected.js").is_file()
    if bundle.endswith(".share"):
        attributes = info["NSExtension"]["NSExtensionAttributes"]
        assert attributes["NSExtensionActivationRule"]["NSExtensionActivationSupportsWebPageWithMaxCount"] == 1
        script = extbase / (attributes["NSExtensionJavaScriptPreprocessingFile"] + ".js")
        assert "var ExtensionPreprocessingJS" in script.read_text()
        print("PASS: Share extension bundles Safari page preprocessing")
    seen.add(bundle)
    print("Verified signed extension:",bundle)
assert seen == set(expected)
print("PASS: signed group entitlement and all extension profiles verified")
if main_authorized: print("PASS: main app group profile authorization verified")
