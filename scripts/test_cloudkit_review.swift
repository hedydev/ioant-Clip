import Foundation
@main struct CloudKitReviewTest {
    static func main() {
        #if CLIP_CLOUDKIT_UI_REVIEW
        precondition(LibraryLocation.isCloudReview)
        precondition(LibraryLocation.notesURL.deletingLastPathComponent().lastPathComponent == "ioant-Clip-CloudKit-UI-Review")
        precondition(CloudKitReviewConfiguration.zoneName == "ioantClipUIReview-9A41E893-7AB6-4E73-BFC7-70DD052EA175")
        #elseif CLIP_CLOUDKIT_DEVELOPMENT
        precondition(!LibraryLocation.isCloudReview)
        precondition(LibraryLocation.notesURL.deletingLastPathComponent().lastPathComponent == "ioant-Note")
        #elseif CLIP_CLOUDKIT_REVIEW
        precondition(LibraryLocation.isCloudReview)
        precondition(LibraryLocation.notesURL.deletingLastPathComponent().lastPathComponent == "ioant-Clip-CloudKit-Review")
        #else
        precondition(!LibraryLocation.isCloudReview)
        precondition(LibraryLocation.notesURL.deletingLastPathComponent().lastPathComponent == "ioant-Note")
        #endif
        #if !CLIP_CLOUDKIT_UI_REVIEW
        precondition(CloudKitReviewConfiguration.zoneName == "ioantNoteRevisionsV1")
        #endif
        // Test executable has no bundle configuration in either lane.
        precondition(CloudKitReviewConfiguration.current() == nil)
        print("CloudKit review library isolation and missing configuration guard passed")
    }
}
