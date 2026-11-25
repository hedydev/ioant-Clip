"""Generate separate extension build spec and Safari resources. No portal or user-data access."""
import json, pathlib, shutil
root = pathlib.Path(__file__).resolve().parents[1]
generated = root / "GeneratedExtensions"
generated.mkdir(exist_ok=True)
source = root / "BrowserExtension"
core = ["Sources/ClipCore/Capture/SharedCaptureInbox.swift", "Sources/ClipCore/Capture/CaptureLanguage.swift", "Sources/ClipCore/Capture/WebCapture.swift", "Sources/ClipCore/Notes/NotePart.swift"]
targets = {}
def extension_sources(name, original, localized=False):
    dest = generated / name
    dest.mkdir(exist_ok=True)
    for path in [original, *core]:
        source = root / path
        shutil.copyfile(source, dest / source.name)
    if localized:
        shutil.copyfile(root / 'App/Localization/Localizable.xcstrings', dest / 'Localizable.xcstrings')
    return [str(dest.relative_to(root))]

for platform, suffix in (("macOS","macos"), ("iOS","ios")):
    target = "ioant-Clip-" + platform
    safari = target + "-Safari"
    dest = generated / (platform + "Safari")
    shutil.copytree(source, dest, dirs_exist_ok=True)
    manifest = json.loads((dest/"manifest.json").read_text())
    manifest.pop("key",None)
    (dest/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    for name in ("popup.js","localization.js"):
        path = dest/"Popup"/name
        js = path.read_text().replace("chrome.", "(globalThis.browser ?? globalThis.chrome).")
        js = js.replace("com.ioant.clip.capture","com.ioant.clip."+suffix)
        path.write_text(js)
    resources = [{"path":str((dest/name).relative_to(root)), "type":"folder", "buildPhase":"resources"} for name in ("CaptureEngine","Popup","_locales")]
    resources.append({"path":str((dest/"manifest.json").relative_to(root)), "buildPhase":"resources"})
    targets[safari] = {"type":"app-extension","platform":platform,
        "sources":extension_sources(platform+"SafariSources","Extensions/Safari/SafariWebExtensionHandler.swift")+resources,
        "settings":{"base":{"PRODUCT_BUNDLE_IDENTIFIER":"com.ioant.clip."+suffix+".safari","INFOPLIST_FILE":"Config/SafariExtension-Info.plist","APPLICATION_EXTENSION_API_ONLY":"YES","CODE_SIGN_ENTITLEMENTS":"Config/"+("MacSafariExtension" if platform=="macOS" else "CaptureExtension")+".entitlements","SKIP_INSTALL":"YES"}}}
    deps = [{"target":safari,"embed":True}]
    if platform == "iOS":
        share = target + "-Share"
        targets[share] = {"type":"app-extension","platform":"iOS","sources":extension_sources("iOSShareSources","Extensions/Share/ShareViewController.swift",localized=True),"settings":{"base":{"PRODUCT_BUNDLE_IDENTIFIER":"com.ioant.clip.ios.share","INFOPLIST_FILE":"Config/ShareExtension-Info.plist","CODE_SIGN_ENTITLEMENTS":"Config/CaptureExtension.entitlements","APPLICATION_EXTENSION_API_ONLY":"YES","SKIP_INSTALL":"YES","TARGETED_DEVICE_FAMILY":"1,2"}}}
        deps.append({"target":share,"embed":True})
    settings = {"PRODUCT_BUNDLE_IDENTIFIER":"com.ioant.clip."+suffix,"INFOPLIST_FILE":"Config/CloudKitReview-Info.plist","CODE_SIGN_ENTITLEMENTS":"Config/CloudKitExtensions.entitlements","CLIP_CLOUDKIT_CONTAINER":"iCloud.com.ioant.clip","CLIP_CLOUDKIT_SMOKE":"NO","CLIP_CLOUDKIT_UI_REVIEW":"NO","CLIP_CLOUDKIT_DEVELOPMENT":"YES","SWIFT_ACTIVE_COMPILATION_CONDITIONS":"$(inherited) CLIP_CLOUDKIT_REVIEW CLIP_CLOUDKIT_DEVELOPMENT CLIP_CAPTURE_EXTENSIONS"}
    if platform=="macOS": settings["ENABLE_HARDENED_RUNTIME"]="YES"
    else: settings.update({"TARGETED_DEVICE_FAMILY":"1,2","INFOPLIST_KEY_UILaunchScreen_Generation":"YES","INFOPLIST_KEY_UIApplicationSceneManifest_Generation":"YES"})
    targets[target]={"type":"application","platform":platform,"sources":["App","Sources/ClipCore"],"dependencies":deps,"settings":{"base":settings}}
spec={"name":"ioant-Clip","options":{"bundleIdPrefix":"com.ioant","deploymentTarget":{"macOS":"14.0","iOS":"17.0"}},"settings":{"base":{"SWIFT_VERSION":"5.0","GENERATE_INFOPLIST_FILE":"YES","MARKETING_VERSION":"0.1.0","CURRENT_PROJECT_VERSION":"1","INFOPLIST_KEY_CFBundleDisplayName":"ioant-Clip","CODE_SIGN_STYLE":"Automatic","DEVELOPMENT_TEAM":"64RS366WKG"}},"targets":targets}
# JSON is valid YAML; place spec at root so paths are relative to the project.
(root/"GeneratedExtensions"/"project.yml").write_text(json.dumps(spec,indent=2)+"\n")
