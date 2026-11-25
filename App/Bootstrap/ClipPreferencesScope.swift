import Foundation

enum ClipPreferencesScope {
    static let defaults: UserDefaults = {
        #if CLIP_CLOUDKIT_UI_REVIEW
        guard let review = UserDefaults(suiteName: "com.ioant.clip.cloudkit-ui-review") else {
            preconditionFailure("Cannot initialize isolated UI review preferences")
        }
        return review
        #else
        return .standard
        #endif
    }()
    static var windowTitle: String {
        #if CLIP_CLOUDKIT_UI_REVIEW
        "ioant-Clip · iCloud UI Review"
        #else
        "ioant-Clip"
        #endif
    }
}
