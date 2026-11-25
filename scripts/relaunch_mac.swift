import AppKit
import Foundation
let id = "com.ioant.clip.macos"
let path = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
guard Bundle(url: path)?.bundleIdentifier == id else { fatalError("Unexpected app bundle") }
let legacyID = "com.ioant.note.macos"
let legacy = NSRunningApplication.runningApplications(withBundleIdentifier: legacyID)
let allowedLegacyPaths: Set<URL> = [
    path.deletingLastPathComponent().appendingPathComponent("ioant-Note-macOS.app").resolvingSymlinksInPath(),
    URL(fileURLWithPath: path.path.replacingOccurrences(of: "/projects/ioant-clip/", with: "/projects/ioant-note/").replacingOccurrences(of: "/ioant-Clip-macOS.app", with: "/ioant-Note-macOS.app")).resolvingSymlinksInPath()
]
guard legacy.allSatisfy({ app in app.bundleURL.map { allowedLegacyPaths.contains($0.resolvingSymlinksInPath()) } == true }) else {
    fatalError("An independent legacy installation is running; close it before migration.")
}
for app in legacy { guard app.terminate() else { fatalError("Legacy app declined graceful quit") } }
let legacyDeadline = Date().addingTimeInterval(12)
while legacy.contains(where: { !$0.isTerminated }) && Date() < legacyDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
guard legacy.allSatisfy(\.isTerminated) else { fatalError("Legacy app still running; no force kill") }
let old = NSRunningApplication.runningApplications(withBundleIdentifier: id)
for app in old {
    guard app.bundleURL?.resolvingSymlinksInPath() == path else {
        fatalError("Another ioant-Clip installation is running; will not replace it.")
    }
    guard app.terminate() else { fatalError("App declined graceful quit") }
}
let deadline = Date().addingTimeInterval(12)
while old.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
guard old.allSatisfy(\.isTerminated) else { fatalError("App did not quit; no force kill") }
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
process.arguments = ["-a", path.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("Launch failed") }
let launchDeadline = Date().addingTimeInterval(15)
while Date() < launchDeadline {
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.bundleURL?.resolvingSymlinksInPath() == path && $0.isFinishedLaunching && !$0.isTerminated }) {
        print("ioant-Clip running; PID \(app.processIdentifier); bundle path verified")
        exit(0)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}
fatalError("Launch not confirmed")
