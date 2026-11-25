import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var preferences: LanguagePreferences
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("settings.language", selection: $preferences.selection) {
                        ForEach(AppLanguage.allCases) { language in
                            if language == .system {
                                Text("settings.language.system").tag(language)
                            } else {
                                Text(verbatim: language.autonym).tag(language)
                            }
                        }
                    }
                    Text("settings.language.description").font(.caption).foregroundStyle(.secondary)
                } header: { Text("settings.language") }
                AppearanceSettingsSection()
                Section("sync.title") {
                    NavigationLink { SyncSettingsView() } label: {
                        Label("sync.title", systemImage: "icloud")
                    }
                }
            }
            .navigationTitle("settings.title")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 480, idealHeight: 620)
        #endif
    }
}
