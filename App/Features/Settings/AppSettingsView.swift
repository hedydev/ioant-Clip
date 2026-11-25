import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var preferences: LanguagePreferences
    var body: some View {
        ModalScrollPage {
            ModalSection(title: "settings.language") {
                Picker(selection: $preferences.selection) {
                    ForEach(AppLanguage.allCases) { language in
                        if language == .system {
                            Text(verbatim: preferences.localized("settings.language.system")).tag(language)
                        } else {
                            Text(verbatim: language.autonym).tag(language)
                        }
                    }
                } label: { Text(verbatim: preferences.localized("settings.language")) }
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: preferences.localized("settings.language")))
                .frame(maxWidth: .infinity, alignment: .leading)
                ModalDescription(key: "settings.language.description")
            }
            Divider()
            AppearanceSettingsSection()
            Divider()
            ExtensionSettingsSection()
        }
    }
}
