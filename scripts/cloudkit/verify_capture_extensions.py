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
