import SwiftUI

struct CloudKitSettingsSection: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var language: LanguagePreferences
    @EnvironmentObject private var controller: CloudSyncController
    private var enrollment: SyncEnrollment? { store.enrollment }
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.medium) {
            Label("iCloud", systemImage: "icloud").font(.headline)
            if !controller.available {
                ModalDescription(key: "sync.cloudkit.required")
            } else {
                ModalDescription(key: LibraryLocation.isCloudReview ? "sync.review.description" : "sync.development.description")
            }
            if let enrollment {
                Label { Text(verbatim: language.localized(enrollment.isPaused ? "sync.paused" : "sync.bound")) } icon: { Image(systemName: enrollment.isPaused ? "pause.circle" : "link") }
                if controller.available {
                    HStack {
                        Button {
                            let resume = enrollment.isPaused
                            controller.setPaused(!resume, store: store)
                            if resume { Task { await controller.syncNow(store: store) } }
                        } label: { Text(verbatim: language.localized(enrollment.isPaused ? "sync.resume" : "sync.pause")) }
                        .disabled(controller.busy)
                        .accessibilityIdentifier("clip-sync-pause-resume")
                        Button { Task { await controller.syncNow(store: store) } } label: { Text(verbatim: language.localized("sync.now")) }
                            .buttonStyle(.borderedProminent)
                            .disabled(controller.busy || enrollment.isPaused)
                            .accessibilityIdentifier("clip-sync-now")
                    }
                }
            } else if controller.available {
                ModalDescription(key: "sync.consent.description")
                Button { Task { await controller.prepareEnrollment(store: store) } } label: { Text(verbatim: language.localized("sync.connect")) }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.busy)
                    .accessibilityIdentifier("clip-sync-connect")
            } else {
                Text(verbatim: language.localized("sync.disconnected")).foregroundStyle(.secondary)
            }
            switch controller.phase {
            case .checking:
                ProgressView { Text(verbatim: language.localized("sync.checking")) }
            case .syncing:
                ProgressView { Text(verbatim: language.localized("sync.running")) }
            case .failed(let key):
                ModalDescription(key: key)
            case .idle: EmptyView()
            }
            if let date = controller.lastSuccess {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: language.localized("sync.lastSuccess")).font(.caption)
                    Text(date, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog(Text(verbatim: language.localized("sync.consent.title")), isPresented: Binding(get: { controller.pendingAccount != nil }, set: { if !$0 { controller.cancelEnrollment() } }), titleVisibility: .visible) {
            Button { controller.approveEnrollment(store: store) } label: { Text(verbatim: language.localized("sync.consent.confirm")) }
                .accessibilityIdentifier("clip-sync-confirm")
            Button(role: .cancel) { controller.cancelEnrollment() } label: { Text(verbatim: language.localized("common.cancel")) }
        } message: {
            Text(verbatim: language.localized("sync.consent.description"))
        }
    }
}
