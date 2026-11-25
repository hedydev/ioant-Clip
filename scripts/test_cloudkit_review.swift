import Foundation
@main struct CloudKitReviewTest {
    static func main() {
        #if CLIP_CLOUDKIT_REVIEW
        precondition(LibraryLocation.isCloudReview)
        precondition(LibraryLocation.notesURL.deletingLastPathComponent().lastPathComponent == "ioant-Clip-CloudKit-Review")
        #else
        precondition(!LibraryLocation.isCloudReview)
        precondition(LibraryLocation.notesURL.deletingLastPathComponent().lastPathComponent == "ioant-Note")
        #endif
        // Test executable has no bundle configuration in either lane.
        precondition(CloudKitReviewConfiguration.current() == nil)
        print("CloudKit review library isolation and missing configuration guard passed")
    }
}
