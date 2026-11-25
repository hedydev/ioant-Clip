import Foundation

/// Test lanes are isolated. Signed development deliberately retains the daily library.
enum LibraryLocation {
    static var isCloudReview: Bool {
        #if CLIP_CLOUDKIT_REVIEW && !CLIP_CLOUDKIT_DEVELOPMENT
        true
        #else
        false
        #endif
    }
    // Keep the original daily directory so Mac data and old queued captures
    // remain available. On iOS the bundle ID still determines the sandbox.
    static var directoryName: String {
        #if CLIP_CLOUDKIT_UI_REVIEW
        "ioant-Clip-CloudKit-UI-Review"
        #else
        isCloudReview ? "ioant-Clip-CloudKit-Review" : "ioant-Note"
        #endif
    }
    static var notesURL: URL {
        URL.applicationSupportDirectory.appending(path: directoryName).appending(path: "notes.json")
    }
}
