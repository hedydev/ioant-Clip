import AppKit
import ApplicationServices
import Foundation

// Inspect only the running, known daily Clip app. Do not change its language,
// settings, content, cloud enrollment, or any other application.
guard AXIsProcessTrusted() else {
    print("BLOCKED: Accessibility permission is not available to this verifier")
    exit(2)
}
let args = CommandLine.arguments
let path = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath().path
let appCandidates = NSRunningApplication.runningApplications(withBundleIdentifier: "com.ioant.clip.macos").filter { !$0.isTerminated }
guard appCandidates.count == 1, let app = appCandidates.first,
      app.bundleURL?.resolvingSymlinksInPath().path == path else {
    fatalError("Not the expected daily Clip process")
}
let root = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(root, 1.0)
func attribute(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success else { return nil }
    return value
}
func string(_ node: AXUIElement, _ key: String) -> String? { attribute(node, key) as? String }
func children(_ node: AXUIElement, _ key: String = "AXChildren") -> [AXUIElement] {
    attribute(node, key) as? [AXUIElement] ?? []
}
func nodes(_ node: AXUIElement, depth: Int = 0, budget: inout Int) -> [AXUIElement] {
    guard depth < 16, budget > 0 else { return [] }
    budget -= 1
    return [node] + children(node).flatMap { nodes($0, depth: depth + 1, budget: &budget) }
}
func sheetNodes() -> [AXUIElement] {
    let windows = children(root, "AXWindows")
    return windows.flatMap { window in
        let sheets = children(window, "AXSheets")
        if !sheets.isEmpty { return sheets }
        var limit = 700
        return nodes(window, budget: &limit).filter {
            let role = string($0,"AXRole")
            return role == "AXSheet" || role == "AXDialog"
        }
    }
}
let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]
let strings = catalog["strings"] as! [String: [String: Any]]
let support = URL.applicationSupportDirectory
let preference = support.appending(path: "ioant-Clip/NativeMessaging/interface-language.json")
guard let code = CaptureLanguage.read(from: preference) else { fatalError("No verified application language receipt") }
func text(_ key: String, _ locale: String) -> String {
    let values = strings[key]!["localizations"] as! [String: Any]
    let value = values[locale] as! [String: Any]
    return (value["stringUnit"] as! [String: Any])["value"] as! String
}
func labels(_ sheets: [AXUIElement]) -> Set<String> {
    var budget = 900
    return Set(sheets.flatMap { nodes($0, budget: &budget) }.flatMap { element in
        ["AXTitle","AXDescription","AXValue","AXHelp"].compactMap { string(element, $0) }
    })
}
let settingsKeys = ["settings.language","settings.appearance","settings.extensions"]
let initial = sheetNodes()
if initial.isEmpty {
    var budget = 1000
    let match = nodes(root, budget: &budget).filter { string($0, "AXIdentifier") == "clip-settings" }
    guard match.count == 1, AXUIElementPerformAction(match[0], kAXPressAction as CFString) == .success else {
        print("BLOCKED: could not open exact Settings toolbar action")
        exit(2)
    }
} else if !settingsKeys.contains(where: { key in labels(initial).contains(text(key, code)) }) {
    print("BLOCKED: another modal is already open; did not dismiss it")
    exit(2)
}
let expectedKeys = ["settings.language","settings.appearance","settings.extensions","settings.appearance.mode","settings.appearance.accent","settings.appearance.reset","settings.extensions.refresh","common.done"]
var found = Set<String>()
for _ in 0..<12 {
    let visible = labels(sheetNodes())
    found = Set(expectedKeys.filter { key in visible.contains(where: { $0 == text(key, code) }) })
    if found.count >= 5 && settingsKeys.allSatisfy({ found.contains($0) }) { break }
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
}
print("Application language:", code)
print("Settings accessibility labels matched:", found.sorted().joined(separator: ", "))
guard found.count >= 5 && settingsKeys.allSatisfy({ found.contains($0) }) else {
    print("BLOCKED: actual sheet labels not sufficiently observable; no settings were changed")
    exit(2)
}
print("PASS: actual running settings sheet contains expected localized section and control labels")

let observed = labels(sheetNodes())
let stateKeys = ["settings.extensions.checking","settings.extensions.notEmbedded","settings.extensions.manual","settings.extensions.enabled","settings.extensions.disabled","settings.extensions.unknown","settings.extensions.registered","settings.extensions.notRegistered","settings.extensions.noContact","settings.extensions.noActivity","settings.extensions.lastContact","settings.extensions.lastQueued"]
for key in stateKeys where observed.contains(text(key,code)) {
    print("Live settings extension label:",key)
}
