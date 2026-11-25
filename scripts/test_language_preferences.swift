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
        precondition(CaptureLanguage.resolve(selection: "system", preferred: ["zh-TW", "en-US"]) == "zh-Hant")
        precondition(CaptureLanguage.resolve(selection: "system", preferred: ["zh-CN"]) == "zh-Hans")
        precondition(CaptureLanguage.resolve(selection: "system", preferred: ["fr-FR", "ja-JP"]) == "ja")
        precondition(CaptureLanguage.resolve(selection: "ko", preferred: ["en-US"]) == "ko")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let receipt = temporary.appendingPathComponent("interface-language.json")
        for code in CaptureLanguage.codes {
            try! CaptureLanguage.write(code, to: receipt)
            precondition(CaptureLanguage.read(from: receipt) == code)
        }
        print("Language preference persistence, canonical locale and extension language handoff passed")
    }
}
