import Foundation
import AppKit

@main struct RestartBlockedClip {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        let path = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath()
        let id = "com.ioant.clip.macos"
        let fm = FileManager.default
        guard let target = Bundle(url: path), target.bundleIdentifier == id,
              target.object(forInfoDictionaryKey: "ClipCloudKitDevelopment") as? String == "YES",
              target.object(forInfoDictionaryKey: "ClipCloudKitUIReview") as? String == "NO",
              target.object(forInfoDictionaryKey: "ClipCloudKitSmoke") as? String == "NO" else { throw NSError(domain:"UnexpectedTarget",code:1) }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { !$0.isTerminated }
        guard apps.count <= 1,
              NSRunningApplication.runningApplications(withBundleIdentifier: "com.ioant.note.macos").isEmpty else { throw NSError(domain:"UnexpectedConcurrentClient",code:1) }
        guard let app = apps.first else { print("Prior client already stopped"); return }
        guard app.bundleURL?.resolvingSymlinksInPath().path == path.path else { throw NSError(domain:"UnexpectedProcessPath",code:1) }
        let pid = app.processIdentifier
        _ = app.terminate()
        let deadline = Date().addingTimeInterval(4)
        while !app.isTerminated && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.1)) }
        if app.isTerminated { print("Prior daily client gracefully stopped"); return }
        // Explicit user requested restart after two confirmed graceful failures.
        // Preserve durable daily state before force quitting this exact app.
        let directory = URL.applicationSupportDirectory.appending(path:"ioant-Note")
        let notes = directory.appending(path:"notes.json")
        let data = try Data(contentsOf:notes)
        guard let library = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let values = library["notes"] as? [[String:Any]],
              Set(values.compactMap {$0["id"] as? String}).count == values.count else { throw NSError(domain:"InvalidLibrary",code:1) }
        let backup = directory.appending(path:"DevelopmentBackups/\(UUID().uuidString)")
        try fm.createDirectory(at:backup,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let copy = backup.appending(path:"notes.json")
        try data.write(to:copy,options:.withoutOverwriting)
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:copy.path)
        guard try Data(contentsOf:copy) == data, try Data(contentsOf:notes) == data else { throw NSError(domain:"LibraryChangedBeforeQuit",code:1) }
        let checkpoint = directory.appending(path:"cloudkit-remote-checkpoint-v1.json")
        if fm.fileExists(atPath:checkpoint.path) {
            let bytes = try Data(contentsOf:checkpoint)
            let destination = backup.appending(path:checkpoint.lastPathComponent)
            try bytes.write(to:destination,options:.withoutOverwriting)
            try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
            guard try Data(contentsOf:destination) == bytes else { throw NSError(domain:"CheckpointBackupFailed",code:1) }
        }
        print("Verified private backup of \(values.count) notes and available checkpoint")
        guard !app.isTerminated, app.processIdentifier == pid,
              app.bundleURL?.resolvingSymlinksInPath().path == path.path,
              NSRunningApplication.runningApplications(withBundleIdentifier:id).filter({!$0.isTerminated}).map(\.processIdentifier) == [pid] else { throw NSError(domain:"ProcessChanged",code:1) }
        guard app.forceTerminate() else { throw NSError(domain:"ForceQuitRejected",code:1) }
        let stop = Date().addingTimeInterval(10)
        while !app.isTerminated && Date() < stop { RunLoop.current.run(until:Date().addingTimeInterval(0.1)) }
        guard app.isTerminated else { throw NSError(domain:"QuitNotConfirmed",code:1) }
        guard try Data(contentsOf:notes) == data else { throw NSError(domain:"LibraryChangedDuringQuit",code:1) }
        print("PASS: only prior daily ioant-Clip PID \(pid) force quit; persisted library unchanged")
    }
}
