"""Read only the signed review's public provisioning metadata.
Report predicates and entitlement names, not raw profiles, UDIDs or certificates.
"""
import datetime
import pathlib
import sys
from profile_inventory import parse_profile, values
from verify_signed_review import verify

platform, raw, team, container = sys.argv[1:]
app = pathlib.Path(raw)
mac = platform == "macOS"
base = app / "Contents" if mac else app
profile = parse_profile(base / ("embedded.provisionprofile" if mac else "embedded.mobileprovision"))
if profile is None:
    raise SystemExit("Embedded profile unreadable")
ent = profile.get("Entitlements", {})
identifier = "com.ioant.clip." + ("macos" if mac else "ios")
application = ent.get("application-identifier") or ent.get("com.apple.application-identifier") or ""
expiry = profile.get("ExpirationDate")
if expiry and expiry.tzinfo is None:
    expiry = expiry.replace(tzinfo=datetime.timezone.utc)
print("Expected app ID:", application.split(".",1)[-1] == identifier)
print("Expected team in TeamIdentifier:", team in values(profile.get("TeamIdentifier")))
print("Expected team entitlement:", ent.get("com.apple.developer.team-identifier") == team)
print("Not expired:", bool(expiry and expiry > datetime.datetime.now(datetime.timezone.utc)))
print("Platform:", sorted(values(profile.get("Platform"))))
print("Profile entitlement names:", sorted(ent))
print("CloudKit profile service allowlist:", sorted(values(ent.get("com.apple.developer.icloud-services"))))
print("Container listed:", container in values(ent.get("com.apple.developer.icloud-container-identifiers")))
print("Development container listed:", container in values(ent.get("com.apple.developer.icloud-container-development-container-identifiers")))
print("Container environment:", sorted(values(ent.get("com.apple.developer.icloud-container-environment"))))
print("get-task-allow:", ent.get("get-task-allow"))
print("mac get-task-allow:", ent.get("com.apple.security.get-task-allow"))
print("ProvisionsAllDevices:", profile.get("ProvisionsAllDevices", False))
print("Provisioned device count:", len(profile.get("ProvisionedDevices", [])))
print("Profile type keys:", sorted(profile.keys()))
try:
    verify(platform, app, team, container)
except (AssertionError, RuntimeError) as error:
    print("Current strict verifier:", str(error))
