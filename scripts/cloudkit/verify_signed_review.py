"""Verify the actual signed app, its embedded profile and explicit CloudKit lane."""
import datetime
import pathlib
import plistlib
import subprocess
import sys
from profile_inventory import matching_profile, parse_profile
from check_development_identity import discover
import hashlib
import tempfile

def run(*args):
    p = subprocess.run(args, capture_output=True, timeout=20)
    if p.returncode:
        raise RuntimeError("verification failed: " + args[0])
    return p

def verify(platform, app, team, container):
    mac = platform == "macOS"
    base = app / "Contents" if mac else app
    with (base / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    bundle = "com.ioant.clip." + ("macos" if mac else "ios")
    assert info.get("CFBundleIdentifier") == bundle, "bundle ID mismatch"
    assert info.get("ClipCloudKitContainer") == container, "Info.plist container mismatch"
    assert info.get("ClipCloudKitEnvironment") == "Development", "Info.plist environment mismatch"
    run("/usr/bin/codesign", "--verify", "--strict", str(app))
    details = run("/usr/bin/codesign", "-d", "--verbose=4", str(app)).stderr.decode().splitlines()
    assert "TeamIdentifier=" + team in details, "signature team mismatch"
    assert any(x.startswith("Authority=Apple Development:") for x in details), "signature is not Apple Development"
    entitlements = plistlib.loads(run("/usr/bin/codesign", "-d", "--entitlements", ":-", str(app)).stdout)
    assert entitlements.get("com.apple.developer.icloud-container-identifiers") == [container], "signed container mismatch"
    assert "CloudKit" in entitlements.get("com.apple.developer.icloud-services", []), "missing signed CloudKit service"
    assert entitlements.get("com.apple.developer.icloud-container-environment") == "Development", "signed environment mismatch"
    profile_path = base / ("embedded.provisionprofile" if mac else "embedded.mobileprovision")
    profile = parse_profile(profile_path)
    assert profile is not None, "embedded profile unavailable"
    match = matching_profile(profile, platform, datetime.datetime.now(datetime.timezone.utc))
    assert match and match[0] == team and container in match[1], "profile does not authorize expected development app/container"
    # Extract only public certificate from the signature, never key material.
    with tempfile.TemporaryDirectory(prefix="clip-review-cert-") as directory:
        prefix = str(pathlib.Path(directory) / "certificate")
        run("/usr/bin/codesign", "-d", "--extract-certificates=" + prefix, str(app))
        leaf = pathlib.Path(prefix + "0").read_bytes()
        _, candidates, _ = discover(team)
        assert hashlib.sha1(leaf).hexdigest().upper() in candidates, "signature identity not locally valid"
        assert leaf in profile.get("DeveloperCertificates", []), "signer not included in profile"
    print("Verified signed app:", bundle)
    print("Verified Apple Development signature, expected team and embedded development profile")
    print("Verified CloudKit container:", container, "environment: Development")
    print("App path:", app)

if __name__ == "__main__":
    platform, path, team, container = sys.argv[1:]
    verify(platform, pathlib.Path(path), team, container)
