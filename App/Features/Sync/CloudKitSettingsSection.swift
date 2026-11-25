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
                ModalDescription(key: LibraryLocation.isCloudReview ? "sync.review.description" : "sync.development.description")
            }
            if let enrollment {
                Label(enrollment.isPaused ? LocalizedStringKey("sync.paused") : LocalizedStringKey("sync.bound"), systemImage: enrollment.isPaused ? "pause.circle" : "link")
                if controller.available {
                    HStack {
                        Button(enrollment.isPaused ? LocalizedStringKey("sync.resume") : LocalizedStringKey("sync.pause")) {
                            let resume = enrollment.isPaused
                            controller.setPaused(!resume, store: store)
                            if resume { Task { await controller.syncNow(store: store) } }
                        }
                        .disabled(controller.busy)
                        .accessibilityIdentifier("clip-sync-pause-resume")
                        Button("sync.now") { Task { await controller.syncNow(store: store) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(controller.busy || enrollment.isPaused)
                            .accessibilityIdentifier("clip-sync-now")
                    }
                }
            } else if controller.available {
                ModalDescription(key: "sync.consent.description")
                Button("sync.connect") { Task { await controller.prepareEnrollment(store: store) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.busy)
                    .accessibilityIdentifier("clip-sync-connect")
            } else {
                Text("sync.disconnected").foregroundStyle(.secondary)
            }
            switch controller.phase {
            case .checking:
                ProgressView("sync.checking")
            case .syncing:
                ProgressView("sync.running")
            case .failed(let key):
                ModalDescription(key: key)
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
                .accessibilityIdentifier("clip-sync-confirm")
            Button("common.cancel", role: .cancel) { controller.cancelEnrollment() }
        } message: {
            Text("sync.consent.description")
        }
    }
}
