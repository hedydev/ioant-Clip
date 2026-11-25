import Foundation

/// Deliberately opt-in at build time. The unsigned daily review build never
/// constructs CKContainer. Only the Development lane is supported for now.
struct CloudKitReviewConfiguration {
    let container: String
    let environment: String
    var namespace: String { container + ":" + environment }
    static func current(bundle: Bundle = .main) -> Self? {
        #if CLIP_CLOUDKIT_REVIEW
        guard let id = bundle.object(forInfoDictionaryKey: "ClipCloudKitContainer") as? String,
              id.hasPrefix("iCloud."), id.count > 7, !id.contains("$("), !id.contains(" "),
              let environment = bundle.object(forInfoDictionaryKey: "ClipCloudKitEnvironment") as? String,
              environment == "Development" else { return nil }
        return Self(container: id, environment: environment)
        #else
        return nil
        #endif
    }
    func transport() -> any RevisionTransport {
        CloudKitRevisionTransport(containerIdentifier: container, environment: environment,
            checkpointURL: LibraryLocation.notesURL.deletingLastPathComponent().appending(path: "cloudkit-remote-checkpoint-v1.json"))
    }
}
