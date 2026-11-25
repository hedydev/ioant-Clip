"""Assert actual generated bundle identities, not just build target names."""
import pathlib
import plistlib
import sys

for raw in sys.argv[1:]:
    bundle = pathlib.Path(raw)
    mac = (bundle / "Contents/Info.plist").is_file()
    path = bundle / ("Contents/Info.plist" if mac else "Info.plist")
    platform = "macos" if mac else "ios"
    with path.open("rb") as f:
        info = plistlib.load(f)
    assert info.get("CFBundleIdentifier") == "com.ioant.clip."+platform, path
    assert info.get("CFBundleDisplayName") == "ioant-Clip", path
    print("Product identity verified:",info["CFBundleIdentifier"])
