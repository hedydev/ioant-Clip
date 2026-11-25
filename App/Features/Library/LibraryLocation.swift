import Foundation

/// Signed review builds must never open the user's existing daily library,
/// even when the cloud configuration is missing or invalid.
enum LibraryLocation {
    static var isCloudReview: Bool {
        #if CLIP_CLOUDKIT_REVIEW
        true
        #else
        false
        #endif
    }
    static var directoryName: String {
        isCloudReview ? "ioant-Clip-CloudKit-Review" : "ioant-Note"
    }
    static var notesURL: URL {
        URL.applicationSupportDirectory.appending(path: directoryName).appending(path: "notes.json")
    }
}
