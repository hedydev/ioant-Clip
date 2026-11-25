import SwiftUI

struct CloudKitSettingsSection: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var controller: CloudSyncController
    private var enrollment: SyncEnrollment? { store.library.syncEnrollment }
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.medium) {
            Label("iCloud", systemImage: "icloud").font(.headline)
            if !controller.available {
                ModalDescription(key: "sync.cloudkit.required")
            } else {
                ModalDescription(key: "sync.review.description")
            }
            if let enrollment {
                Label(enrollment.isPaused ? LocalizedStringKey("sync.paused") : LocalizedStringKey("sync.bound"), systemImage: enrollment.isPaused ? "pause.circle" : "link")
                if controller.available {
                    HStack {
                        Button(enrollment.isPaused ? LocalizedStringKey("sync.resume") : LocalizedStringKey("sync.pause")) {
                            controller.setPaused(!enrollment.isPaused, store: store)
                        }
                        .disabled(controller.busy)
                        Button("sync.now") { Task { await controller.syncNow(store: store) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(controller.busy || enrollment.isPaused)
                    }
                }
            } else if controller.available {
                Button("sync.connect") { Task { await controller.prepareEnrollment(store: store) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.busy)
            } else {
                Text("sync.disconnected").foregroundStyle(.secondary)
            }
            switch controller.phase {
            case .checking:
                ProgressView("sync.checking")
            case .syncing:
                ProgressView("sync.running")
            case .failed(let key):
                ModalDescription(key: LocalizedStringKey(key))
            case .idle: EmptyView()
            }
            if let date = controller.lastSuccess {
                VStack(alignment: .leading, spacing: 4) {
                    Text("sync.lastSuccess").font(.caption)
                    Text(date, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("sync.consent.title", isPresented: Binding(get: { controller.pendingAccount != nil }, set: { if !$0 { controller.cancelEnrollment() } }), titleVisibility: .visible) {
            Button("sync.consent.confirm") { controller.approveEnrollment(store: store) }
            Button("common.cancel", role: .cancel) { controller.cancelEnrollment() }
        } message: {
            Text("sync.consent.description")
        }
    }
}
