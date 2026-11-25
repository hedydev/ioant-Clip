import Foundation
import SwiftUI

@main struct ThemePreferenceTest {
    @MainActor static func main() {
        let name = "ioant-clip-theme-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = ThemePreferences(defaults: defaults)
        precondition(model.appearance == .system && model.accent == .blue)
        precondition(AppAppearance.system.preferredScheme == nil)
        precondition(AppAppearance.light.preferredScheme == .light)
        precondition(AppAppearance.dark.preferredScheme == .dark)
        precondition(AppAccent.allCases.count == 7)
        for appearance in AppAppearance.allCases {
            for accent in AppAccent.allCases {
                model.appearance = appearance
                model.accent = accent
                let restored = ThemePreferences(defaults: defaults)
                precondition(restored.appearance == appearance && restored.accent == accent)
            }
        }
        model.reset()
        precondition(ThemePreferences(defaults: defaults).appearance == .system)
        precondition(ThemePreferences(defaults: defaults).accent == .blue)
        defaults.set("invalid", forKey: ThemePreferences.appearanceKey)
        defaults.set("invalid", forKey: ThemePreferences.accentKey)
        precondition(ThemePreferences(defaults: defaults).appearance == .system)
        precondition(ThemePreferences(defaults: defaults).accent == .blue)
        print("Theme preference: 21 mode/accent combinations, reset and fallback passed")
    }
}
