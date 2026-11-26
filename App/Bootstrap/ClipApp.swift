#if !CLIP_CLOUDKIT_SMOKE && !CLIP_CLOUDKIT_SIM_SMOKE
import SwiftUI

@main struct ClipApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var language: LanguagePreferences
    @StateObject private var theme: ThemePreferences
    @StateObject private var cloudSync: CloudSyncController

    init() {
        let defaults = ClipPreferencesScope.defaults
        let language = LanguagePreferences(defaults: defaults)
        let theme = ThemePreferences(defaults: defaults)
        _language = StateObject(wrappedValue: language)
        _theme = StateObject(wrappedValue: theme)
        _cloudSync = StateObject(wrappedValue: CloudSyncController(
            preferences: CloudPreferencesSync(language: language, theme: theme, defaults: defaults)
        ))
    }
    var body: some Scene {
        WindowGroup(ClipPreferencesScope.windowTitle) {
            AppThemeScope(preferences: theme) {
                AppLocaleScope(preferences: language) { LibraryView().environmentObject(store) }
            }
                .defaultAppStorage(ClipPreferencesScope.defaults)
                .environmentObject(cloudSync)
                .modifier(SyncForegroundSchedule(controller: cloudSync, store: store))
            #if os(macOS)
                .frame(minWidth: PresentationMetrics.mainMinimum.width, minHeight: PresentationMetrics.mainMinimum.height)
                .background(MainWindowSizing())
            #endif
                .task {
                    while !Task.isCancelled {
                        store.receivePendingCaptures()
                        do { try await Task.sleep(for: .seconds(1)) }
                        catch { break }
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: PresentationMetrics.mainDefault.width, height: PresentationMetrics.mainDefault.height)
        .windowResizability(.contentMinSize)
        #endif
    }
}


#endif
