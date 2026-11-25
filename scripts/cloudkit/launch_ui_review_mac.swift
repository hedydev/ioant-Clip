import AppKit
import Foundation

let app = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
let id = "com.ioant.clip.macos"
func running() -> [NSRunningApplication] { NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { !$0.isTerminated } }
func isReview(_ process: NSRunningApplication) -> Bool { process.bundleURL?.resolvingSymlinksInPath() == app }
guard let bundle = Bundle(url: app), bundle.bundleIdentifier == id,
      bundle.object(forInfoDictionaryKey: "ClipCloudKitUIReview") as? String == "YES",
      bundle.object(forInfoDictionaryKey: "ClipCloudKitSmoke") as? String == "NO",
      bundle.object(forInfoDictionaryKey: "ClipCloudKitContainer") as? String == "iCloud.com.ioant.clip",
      bundle.object(forInfoDictionaryKey: "ClipCloudKitEnvironment") as? String == "Development" else {
    fatalError("Wrong signed review artifact")
}
let library = URL.applicationSupportDirectory.appending(path: "ioant-Clip-CloudKit-UI-Review")
guard !FileManager.default.fileExists(atPath: library.path) else {
    fatalError("Review library already exists; no implicit launch or enrollment")
}
let original = running()
guard !original.contains(where: isReview) else { fatalError("Review process already running") }
let oldPIDs = Set(original.map(\.processIdentifier))
let launch = Process()
launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
launch.arguments = ["-n", "-a", app.path]
try launch.run()
launch.waitUntilExit()
guard launch.terminationStatus == 0 else { fatalError("Open request failed") }
let deadline = Date().addingTimeInterval(20)
while Date() < deadline {
    if let review = running().first(where: { isReview($0) && $0.isFinishedLaunching }),
       let data = try? Data(contentsOf: library.appending(path: "notes.json")),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        guard (json["notes"] as? [Any])?.isEmpty == true,
              json["syncEnrollment"] == nil || json["syncEnrollment"] is NSNull,
              oldPIDs.isSubset(of: Set(running().map(\.processIdentifier))) else {
            fatalError("Unexpected isolated library state or previous app process")
        }
        print("PASS: signed iCloud UI review running; PID \(review.processIdentifier); isolated empty library; no enrollment")
        print("Existing Clip processes retained: \(oldPIDs.count)")
        exit(0)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}
fatalError("Launch or library initialization not confirmed; reconcile before retry")
