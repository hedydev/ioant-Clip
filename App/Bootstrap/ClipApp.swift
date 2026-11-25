import SwiftUI

@main struct ClipApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var language = LanguagePreferences()
    var body: some Scene {
        WindowGroup {
            AppLocaleScope(preferences: language) { LibraryView().environmentObject(store) }
            #if os(macOS)
                .task {
                    while !Task.isCancelled {
                        store.receivePendingCaptures()
                        do { try await Task.sleep(for: .seconds(1)) }
                        catch { break }
                    }
                }
            #endif
        }
    }
}

