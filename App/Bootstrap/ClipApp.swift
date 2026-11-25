import SwiftUI

@main struct ClipApp: App {
    @StateObject private var store = LibraryStore()
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(store)
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

