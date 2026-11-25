import Foundation

/// Deliberately opt-in at build time. The unsigned daily review build never
/// constructs CKContainer. Only the Development lane is supported for now.
struct CloudKitReviewConfiguration {
    let container: String
    let environment: String
    var namespace: String { container + ":" + environment }
    static var zoneName: String {
        #if CLIP_CLOUDKIT_UI_REVIEW
        "ioantClipUIReview-9A41E893-7AB6-4E73-BFC7-70DD052EA175"
        #else
        "ioantNoteRevisionsV1"
        #endif
    }
    static func current(bundle: Bundle = .main) -> Self? {
        #if CLIP_CLOUDKIT_REVIEW
        guard let id = bundle.object(forInfoDictionaryKey: "ClipCloudKitContainer") as? String,
              id.hasPrefix("iCloud."), id.count > 7, !id.contains("$("), !id.contains(" "),
              let environment = bundle.object(forInfoDictionaryKey: "ClipCloudKitEnvironment") as? String,
              environment == "Development" else { return nil }
        #if CLIP_CLOUDKIT_UI_REVIEW
        guard id == "iCloud.com.ioant.clip",
              bundle.object(forInfoDictionaryKey: "ClipCloudKitUIReview") as? String == "YES",
              bundle.object(forInfoDictionaryKey: "ClipCloudKitSmoke") as? String == "NO" else { return nil }
        #endif
        return Self(container: id, environment: environment)
        #else
        return nil
        #endif
    }
    func transport() -> any RevisionTransport {
        CloudKitRevisionTransport(containerIdentifier: container, environment: environment, zoneName: Self.zoneName,
            checkpointURL: LibraryLocation.notesURL.deletingLastPathComponent().appending(path: "cloudkit-remote-checkpoint-v1.json"))
    }
}
