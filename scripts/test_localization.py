import json, pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[1]
catalog = json.loads((root / "App/Localization/Localizable.xcstrings").read_text())
keys = catalog["strings"]
locales = {"en","zh-Hans","zh-Hant","ja","ko"}
for key, value in keys.items():
    assert set(value["localizations"]) == locales, key
    for locale, entry in value["localizations"].items():
        text = entry["stringUnit"]["value"]
        assert text.strip(), (key, locale)
        assert sorted(re.findall(r"%lld|%@", text)) == sorted(re.findall(r"%lld|%@", key)), (key, locale)
for file in (root / "App").rglob("*.swift"):
    source = file.read_text()
    for key in re.findall(r'"((?:common|library|reader|tags|editor|color|sync|settings|error)\.[a-zA-Z.]+)(?:\\\([^"]+\))?"', source):
        assert key in keys or key+" %lld" in keys or key+" %@" in keys, (file, key)
    for key in re.findall(r'"((?:library|tags)\.[a-zA-Z.]+) \\\([^"]+\)"', source):
        assert key+" %lld" in keys or key+" %@" in keys, (file, key)
print(f"Native localization coverage: {len(keys)} keys x {len(locales)} locales")
# Optional verification of actual compiled resource bundles.
for arg in sys.argv[1:]:
    bundle=pathlib.Path(arg)
    base=bundle/"Contents/Resources" if (bundle/"Contents/Resources").is_dir() else bundle
    for locale in locales:
        path=base/(locale+".lproj")/"Localizable.strings"
        assert path.is_file(), str(path)
    print("Compiled locale resources:",bundle.name)
