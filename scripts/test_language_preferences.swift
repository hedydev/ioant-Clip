import Foundation
import SwiftUI

@main struct LanguagePreferenceTest {
    @MainActor static func main() {
        let name = "ioant-clip-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = LanguagePreferences(defaults: defaults)
        precondition(model.selection == .system)
        precondition(model.resolvedLocale(system: Locale(identifier: "fr_FR")).identifier == "en")
        for language in AppLanguage.allCases where language != .system {
            model.selection = language
            let restored = LanguagePreferences(defaults: defaults)
            precondition(restored.selection == language)
            precondition(restored.resolvedLocale(system: Locale(identifier:"en")).identifier == Locale(identifier:language.rawValue).identifier)
        }
        defaults.set("invalid",forKey:"ioant.clip.preferences.language.v1")
        precondition(LanguagePreferences(defaults:defaults).selection == .system)
        print("Language preference persistence and fallback passed")
    }
}
