import AppKit
import Foundation
for id in ["com.ioant.clip.macos", "com.ioant.note.macos"] {
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) where !app.isTerminated {
        let url = app.bundleURL?.resolvingSymlinksInPath()
        let bundle = url.flatMap(Bundle.init(url:))
        print("Clip PID \(app.processIdentifier) bundle \(url?.path ?? "<none>")")
        for key in ["ClipCloudKitDevelopment","ClipCloudKitUIReview","ClipCloudKitSmoke","ClipCloudKitEnvironment"] {
            print("\(key): \(bundle?.object(forInfoDictionaryKey: key) ?? "<absent>")")
        }
    }
}
let notes = URL.applicationSupportDirectory.appending(path: "ioant-Note/notes.json")
let data = try Data(contentsOf: notes)
let library = try JSONSerialization.jsonObject(with: data) as! [String:Any]
print("Daily library notes:", (library["notes"] as? [Any])?.count ?? -1)
print("Daily enrollment present:", library["syncEnrollment"] != nil && !(library["syncEnrollment"] is NSNull))
