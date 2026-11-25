import AppKit
import Foundation

let id = "com.ioant.clip.macos"
let args = CommandLine.arguments
let path = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath()
let derived = URL(fileURLWithPath: args[2]).resolvingSymlinksInPath()
let firstActivation = args.count > 3 && args[3] == "first-cloud-development"
guard let target = Bundle(url: path), target.bundleIdentifier == id,
      target.object(forInfoDictionaryKey: "ClipCloudKitDevelopment") as? String == "YES",
      target.object(forInfoDictionaryKey: "ClipCloudKitUIReview") as? String == "NO",
      target.object(forInfoDictionaryKey: "ClipCloudKitSmoke") as? String == "NO" else { fatalError("Unexpected signed development target") }
let fm = FileManager.default
let support = URL.applicationSupportDirectory
let notes = support.appending(path: "ioant-Note/notes.json")
func readLibrary() throws -> ([String: Any], Data) {
    let data = try Data(contentsOf: notes)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let _ = json["notes"] as? [[String: Any]] else { fatalError("Invalid daily library") }
    return (json, data)
}
func ids(_ json: [String: Any]) -> Set<String> {
    Set((json["notes"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
}
let oldUnsigned = derived.appending(path: "macOS/Build/Products/Debug/ioant-Clip-macOS.app").resolvingSymlinksInPath()
let oldReview = derived.appending(path: "CloudKitUIReview/macOS/Build/Products/Debug/ioant-Clip-macOS.app").resolvingSymlinksInPath()
let legacyID = "com.ioant.note.macos"
guard NSRunningApplication.runningApplications(withBundleIdentifier: legacyID).isEmpty else {
    fatalError("Legacy installation running; refusing concurrent daily library access")
}
let old = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { !$0.isTerminated }
for proc in old {
    guard let url = proc.bundleURL?.resolvingSymlinksInPath(), [path, oldUnsigned, oldReview].contains(url) else {
        fatalError("Unknown Clip installation running; no process terminated")
    }
    if url == oldReview {
        guard Bundle(url: url)?.object(forInfoDictionaryKey: "ClipCloudKitUIReview") as? String == "YES" else {
            fatalError("Unknown review process")
        }
    }
}
if firstActivation {
    let (initial, _) = try readLibrary()
    guard initial["syncEnrollment"] == nil || initial["syncEnrollment"] is NSNull else {
        fatalError("Existing cloud binding; inspect before first activation")
    }
}
for proc in old {
    guard proc.terminate() else { fatalError("Clip declined graceful quit") }
}
let deadline = Date().addingTimeInterval(15)
while old.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
guard old.allSatisfy(\.isTerminated) else { fatalError("Clip still running; no force kill") }
let (before, beforeData) = try readLibrary()
let existingIDs = ids(before)
guard existingIDs.count == (before["notes"] as? [[String: Any]])?.count else { fatalError("Invalid note identities") }
if firstActivation {
    guard before["syncEnrollment"] == nil || before["syncEnrollment"] is NSNull else { fatalError("Unexpected enrollment") }
    let backupRoot = support.appending(path: "ioant-Note/DevelopmentBackups")
    try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let backup = backupRoot.appending(path: UUID().uuidString + ".json")
    try beforeData.write(to: backup, options: .withoutOverwriting)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
    guard try Data(contentsOf: backup) == beforeData else { fatalError("Backup verification failed") }
    print("Verified local backup; existing notes: \(existingIDs.count); enrollment absent")
    print("Backup path: \(backup.path)")
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
process.arguments = ["-n", "-a", path.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("Launch failed") }
let launchDeadline = Date().addingTimeInterval(20)
while Date() < launchDeadline {
    let live = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { !$0.isTerminated }
    if live.count == 1, let app = live.first, app.bundleURL?.resolvingSymlinksInPath() == path, app.isFinishedLaunching {
        let (after, afterData) = try readLibrary()
        guard existingIDs.isSubset(of: ids(after)) else { fatalError("Daily notes missing after launch") }
        if firstActivation {
            guard after["syncEnrollment"] == nil || after["syncEnrollment"] is NSNull else { fatalError("Unexpected cloud enrollment") }
        }
        print("PASS: signed development client PID \(app.processIdentifier); previous \(existingIDs.count) note IDs retained; library bytes unchanged: \(afterData == beforeData)")
        print("Cloud enrollment present: \(after["syncEnrollment"] != nil && !(after["syncEnrollment"] is NSNull))")
        exit(0)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}
fatalError("Launch not confirmed; reconcile before repeating")
