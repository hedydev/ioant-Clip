import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var preferences: LanguagePreferences
    var body: some View {
        ModalScrollPage {
            ModalSection(title: "settings.language") {
                Picker("settings.language", selection: $preferences.selection) {
                    ForEach(AppLanguage.allCases) { language in
                        if language == .system {
                            Text("settings.language.system").tag(language)
                        } else {
                            Text(verbatim: language.autonym).tag(language)
                        }
                    }
                }
                .labelsHidden()
                .accessibilityLabel(Text("settings.language"))
                .frame(maxWidth: .infinity, alignment: .leading)
                ModalDescription(key: "settings.language.description")
            }
            Divider()
            AppearanceSettingsSection()
        }
    }
}
