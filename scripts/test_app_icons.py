"""Check App Store source artwork and the icon embedded in each built app."""
import json
from pathlib import Path
import plistlib
import struct
import sys


def check_catalogs():
    assets = Path(__file__).resolve().parents[1] / "Resources" / "AppIcons"
    for platform, color_type in (("iOS", 2), ("macOS", 6)):
        icon_set = assets / f"{platform}.xcassets" / "AppIcon.appiconset"
        images = json.loads((icon_set / "Contents.json").read_text())["images"]
        slots = {(image["size"], image.get("scale", "1x")) for image in images}
        expected = (
            {("1024x1024", "1x")}
            if platform == "iOS"
            else {(f"{size}x{size}", scale) for size in (16, 32, 128, 256, 512) for scale in ("1x", "2x")}
        )
        assert slots == expected and len(images) == len(expected), platform
        for image in images:
            path = icon_set / image["filename"]
            pixels = int(image["size"].split("x")[0]) * int(image.get("scale", "1x")[0])
            with path.open("rb") as stream:
                header = stream.read(26)
            assert header[:8] == b"\x89PNG\r\n\x1a\n", path
            assert struct.unpack_from(">IIBB", header, 16) == (pixels, pixels, 8, color_type), path
    print("App icon source dimensions and PNG color types verified")


def check_bundle(bundle):
    mac = (bundle / "Contents/Info.plist").is_file()
    info = plistlib.loads((bundle / ("Contents/Info.plist" if mac else "Info.plist")).read_bytes())
    if mac:
        name = Path(info["CFBundleIconFile"]).stem
        icon = bundle / "Contents/Resources" / f"{name}.icns"
        with icon.open("rb") as stream:
            assert stream.read(4) == b"icns", icon
    else:
        assert (bundle / "Assets.car").stat().st_size > 0, bundle
        for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
            primary = info[key]["CFBundlePrimaryIcon"]
            assert primary["CFBundleIconName"] == "AppIcon", key
            for name in primary["CFBundleIconFiles"]:
                assert any(bundle.glob(f"{name}*.png")), name
    print("App icon verified in", bundle.name)


if __name__ == "__main__":
    check_catalogs()
    for argument in sys.argv[1:]:
        check_bundle(Path(argument))
