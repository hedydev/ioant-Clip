import AppKit
import Foundation
let id = "com.ioant.note.macos"
let path = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
guard Bundle(url: path)?.bundleIdentifier == id else { fatalError("Unexpected app bundle") }
let old = NSRunningApplication.runningApplications(withBundleIdentifier: id)
for app in old {
    guard app.bundleURL?.resolvingSymlinksInPath() == path else {
        fatalError("Another ioant-Note installation is running; will not replace it.")
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
        print("ioant-Note running; PID \(app.processIdentifier); bundle path verified")
        exit(0)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}
fatalError("Launch not confirmed")
