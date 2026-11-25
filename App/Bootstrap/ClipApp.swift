#if !CLIP_CLOUDKIT_SMOKE && !CLIP_CLOUDKIT_SIM_SMOKE
import SwiftUI

@main struct ClipApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var language = LanguagePreferences()
    @StateObject private var theme = ThemePreferences()
    @StateObject private var cloudSync = CloudSyncController()
    var body: some Scene {
        WindowGroup {
            AppThemeScope(preferences: theme) {
                AppLocaleScope(preferences: language) { LibraryView().environmentObject(store) }
            }
                .environmentObject(cloudSync)
                .modifier(SyncForegroundSchedule(controller: cloudSync, store: store))
            #if os(macOS)
                .frame(minWidth: PresentationMetrics.mainMinimum.width, minHeight: PresentationMetrics.mainMinimum.height)
                .background(MainWindowSizing())
                .task {
                    while !Task.isCancelled {
                        store.receivePendingCaptures()
                        do { try await Task.sleep(for: .seconds(1)) }
                        catch { break }
                    }
                }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: PresentationMetrics.mainDefault.width, height: PresentationMetrics.mainDefault.height)
        .windowResizability(.contentMinSize)
        #endif
    }
}


#endif
