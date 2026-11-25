import SwiftUI

/// Native scene lifecycle. No background service, timer promises or push.
struct SyncForegroundSchedule: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let controller: CloudSyncController
    let store: LibraryStore
    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active, controller.available else { return }
            while !Task.isCancelled {
                await controller.syncIfDue(store: store)
                do { try await Task.sleep(for: .seconds(15)) }
                catch { break }
            }
        }
    }
}
