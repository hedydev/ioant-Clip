import json, pathlib, re
root=pathlib.Path(__file__).resolve().parents[1]/"BrowserExtension"
locales=["en","zh_CN","zh_TW","ja","ko"]
catalogs=[json.loads((root/"_locales"/l/"messages.json").read_text()) for l in locales]
keys=set(catalogs[0])
for locale, catalog in zip(locales,catalogs):
    assert set(catalog)==keys, locale
    assert all(v["message"].strip() for v in catalog.values()),locale
html=(root/"Popup/popup.html").read_text()
assert len(re.findall(r'data-i18n="([^"]+)"',html))==7
for path in [root/"Popup/popup.js",root/"Popup/localization.js",root/"CaptureEngine/capture.js",root/"CaptureEngine/viewport.js"]:
    for key in re.findall(r"'((?:error|status)_[a-z_]+)'",path.read_text()):
        assert key in keys,(path,key)
for key in re.findall(r'data-i18n="([^"]+)"',html):
    assert key in keys,key
manifest=json.loads((root/"manifest.json").read_text())
assert manifest["default_locale"]=="en"
for key in re.findall(r'__MSG_([a-z_]+)__',json.dumps(manifest)):
    assert key in keys,key
assert all((root/"Popup"/path).resolve().is_file() for path in re.findall(r'<script src="([^"]+)"',html))
print(f"Extension localization coverage: {len(keys)} keys x {len(locales)} locales")
