import Foundation
import SwiftUI

@main struct VerifySettingsLocale {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        let bundle = Bundle(url: URL(fileURLWithPath: args[1]))!
        let source = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]
        let strings = source["strings"] as! [String: [String: Any]]
        let name = "ioant-clip-settings-localization-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = LanguagePreferences(defaults: defaults)
        let keys = strings.keys.filter { key in
            !key.contains("%") && ["settings.", "common.", "color.", "sync.", "library.all", "library.paste"].contains { key.hasPrefix($0) }
        }.sorted()
        for selection in AppLanguage.allCases where selection != .system {
            preferences.selection = selection
            for key in keys {
                let entry = strings[key]!["localizations"] as! [String: Any]
                let value = entry[selection.rawValue] as! [String: Any]
                let unit = value["stringUnit"] as! [String: Any]
                let expected = unit["value"] as! String
                let actual = preferences.localized(key, bundle: bundle)
                guard actual == expected else {
                    fatalError("Settings lookup \(selection.rawValue) \(key): \(actual) != \(expected)")
                }
            }
            print("PASS: \(selection.rawValue): \(keys.count) actual bundled settings/control strings match catalog")
        }
        print("PASS: explicit native settings localization uses selected language, not process locale")
    }
}
