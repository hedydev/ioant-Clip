import pathlib, plistlib, struct, subprocess, sys, tempfile

app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / "Info.plist").read_bytes())
bundle = sys.argv[2] if len(sys.argv) >= 3 else "com.ioant.clip.ios.simsmoke"
mode = sys.argv[3] if len(sys.argv) == 4 else "isolated"
assert mode in ("isolated", "registered", "ui")
assert bundle in ("com.ioant.clip.ios.simsmoke", "com.ioant.clip.ios")
assert info["CFBundleIdentifier"] == bundle
assert info["ClipCloudKitContainer"] == "iCloud.com.ioant.clip"
assert info["ClipCloudKitEnvironment"] == "Development"
assert info["ClipCloudKitSmoke"] == ("NO" if mode == "ui" else "YES")
if mode == "ui":
    assert bundle == "com.ioant.clip.ios" and info["ClipCloudKitUIReview"] == "YES"
    assert isinstance(info.get("UIApplicationSceneManifest"), dict), "missing iOS scene manifest"
subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(app)], check=True)

def simulator_entitlements(executable):
    # Simulator runs on the macOS kernel. Xcode embeds iOS entitlements in the
    # Mach-O __TEXT section, distinct from the host ad hoc code signature.
    with tempfile.TemporaryDirectory() as tmp:
        raw = executable.read_bytes()
        if raw[:4] != b"\xcf\xfa\xed\xfe":
            thin = pathlib.Path(tmp) / "arm64"
            subprocess.run(["/usr/bin/lipo", str(executable), "-thin", "arm64", "-output", str(thin)], check=True)
            raw = thin.read_bytes()
        assert raw[:4] == b"\xcf\xfa\xed\xfe", "expected 64-bit little-endian Mach-O"
        ncmds, sizeofcmds = struct.unpack_from("<II", raw, 16)
        pos, limit = 32, 32 + sizeofcmds
        assert limit <= len(raw)
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", raw, pos)
            assert size >= 8 and pos + size <= limit
            if cmd == 0x19:
                nsects = struct.unpack_from("<I", raw, pos + 64)[0]
                assert size >= 72 + nsects * 80
                for i in range(nsects):
                    sec = pos + 72 + i * 80
                    name = raw[sec:sec+16].split(b"\0", 1)[0]
                    segment = raw[sec+16:sec+32].split(b"\0", 1)[0]
                    if (segment, name) == (b"__TEXT", b"__entitlements"):
                        length, offset = struct.unpack_from("<QI", raw, sec + 40)
                        assert length > 0 and offset + length <= len(raw)
                        return plistlib.loads(raw[offset:offset+length].rstrip(b"\0"))
            pos += size
        raise AssertionError("Xcode simulator executable lacks __TEXT,__entitlements")

ent = simulator_entitlements(app / info["CFBundleExecutable"])
print("Verified embedded simulator entitlement keys:", ", ".join(sorted(ent)))
assert ent.get("com.apple.developer.icloud-container-identifiers") == ["iCloud.com.ioant.clip"], "simulator container entitlement mismatch"
assert "CloudKit" in ent.get("com.apple.developer.icloud-services", []), "simulator CloudKit service missing"
assert ent.get("com.apple.developer.icloud-container-environment") == "Development", "simulator environment mismatch"
if bundle == "com.ioant.clip.ios":
    assert ent.get("application-identifier") == "64RS366WKG." + bundle, "registered application identifier mismatch"
print("PASS: simulator smoke identity, host signature and embedded CloudKit Development entitlements verified; server authorization not yet verified")
