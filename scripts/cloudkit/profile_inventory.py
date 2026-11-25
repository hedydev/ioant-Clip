"""Read-only inventory of locally installed profiles for ioant-Clip only.

Never print raw profiles, certificates, Apple ID, device UDIDs or credentials.
No network, Keychain modification, provisioning updates or app installation.
"""
import datetime
import pathlib
import plistlib
import subprocess

BUNDLES = {"macOS": "com.ioant.clip.macos", "iOS": "com.ioant.clip.ios"}

def values(value):
    if isinstance(value, str):
        return {value}
    if isinstance(value, (list, tuple)):
        return {x for x in value if isinstance(x, str)}
    return set()

def parse_profile(path):
    process = subprocess.run(["/usr/bin/security", "cms", "-D", "-i", str(path)],
                             capture_output=True, timeout=12)
    if process.returncode:
        return None
    return plistlib.loads(process.stdout)

def matching_profile(profile, platform, now):
    ent = profile.get("Entitlements", {})
    app = ent.get("application-identifier") or ent.get("com.apple.application-identifier") or ""
    if "." not in app or app.split(".", 1)[1] != BUNDLES[platform]:
        return None
    expiry = profile.get("ExpirationDate")
    teams = values(profile.get("TeamIdentifier"))
    team = ent.get("com.apple.developer.team-identifier")
    if len(teams) != 1 or team not in teams or not expiry:
        return None
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=datetime.timezone.utc)
    if expiry <= now:
        return None
    allowed = values(profile.get("Platform"))
    if platform == "iOS" and "iOS" not in allowed:
        return None
    if platform == "macOS" and not ({"OSX", "macOS"} & allowed):
        return None
    env = values(ent.get("com.apple.developer.icloud-container-environment"))
    services = values(ent.get("com.apple.developer.icloud-services"))
    containers = values(ent.get("com.apple.developer.icloud-container-identifiers"))
    containers = {x for x in containers if x.startswith("iCloud.") and "*" not in x and "$" not in x}
    if not (ent.get("get-task-allow") is True or ent.get("com.apple.security.get-task-allow") is True):
        return None
    if "CloudKit" not in services or "Development" not in env:
        return None
    return team, containers

def main():
    home = pathlib.Path.home()
    directories = [home / "Library/Developer/Xcode/UserData/Provisioning Profiles",
                   home / "Library/MobileDevice/Provisioning Profiles"]
    profiles = sorted(set(path for directory in directories if directory.is_dir()
                          for path in directory.iterdir()
                          if path.is_file() and path.suffix in {".provisionprofile", ".mobileprovision"}))
    now = datetime.datetime.now(datetime.timezone.utc)
    matches = {platform: set() for platform in BUNDLES}
    failures = 0
    for path in profiles:
        try:
            profile = parse_profile(path)
            if profile is None:
                failures += 1
                continue
            for platform in BUNDLES:
                result = matching_profile(profile, platform, now)
                if result:
                    team, containers = result
                    matches[platform].update((team, container) for container in containers)
        except (ValueError, OSError, subprocess.TimeoutExpired, plistlib.InvalidFileException):
            failures += 1
    print("CloudKit provisioning inventory (local only)")
    print("Profiles scanned:", len(profiles), "unreadable:", failures)
    for platform, pairs in matches.items():
        print(platform, BUNDLES[platform], "eligible team/container combinations:", len(pairs))
    common = matches["macOS"] & matches["iOS"]
    print("Common development team/container combinations:", len(common))
    if len(common) == 1:
        print("READY_FOR_SIGNING_ATTEMPT: shared local provisioning metadata exists; actual signing not verified")
    else:
        print("BLOCKED: configure both explicit bundle IDs and the same development CloudKit container; no signing attempted")
    if failures:
        print("Note: unreadable profiles make the inventory incomplete")

if __name__ == "__main__":
    main()
