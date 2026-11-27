import SwiftUI

struct CloudKitSettingsSection: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var language: LanguagePreferences
    @EnvironmentObject private var controller: CloudSyncController
    private var enrollment: SyncEnrollment? { store.enrollment }
    private struct UsageRevision: Equatable {
        let account: SyncAccount
        let lastSync: Date?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.medium) {
            if let enrollment {
                if enrollment.isPaused {
                    Label { Text(verbatim: language.localized("sync.paused")) } icon: { Image(systemName: "pause.circle") }
                } else if controller.lastSuccess == nil && controller.phase == .idle {
                    Label { Text(verbatim: language.localized("sync.bound")) } icon: { Image(systemName: "link") }
                }
                let url = store.url
                let account = enrollment.account
                let zone = CloudKitReviewConfiguration.zoneName
                StorageUsageRow(label: "sync.usage.remote", revision: UsageRevision(account: account, lastSync: controller.lastSuccess)) {
                    try StorageUsage.syncedBytes(libraryURL: url, account: account, zone: zone)
                }
                if let date = controller.lastSuccess {
                    LabeledContent {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                    } label: { Text(verbatim: language.localized("sync.lastSuccess")) }
                }
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
                Link(destination: URL(string: "https://support.apple.com/108922")!) {
                    Text(verbatim: language.localized("sync.usage.help"))
                }.font(.callout)
            } else {
                Text(verbatim: language.localized("sync.disconnected")).foregroundStyle(.secondary)
                if controller.available {
                    Button { Task { await controller.prepareEnrollment(store: store) } } label: {
                        Text(verbatim: language.localized("sync.connect"))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.busy)
                    .accessibilityIdentifier("clip-sync-connect")
                }
            }
            if !controller.available {
                ModalDescription(key: "sync.cloudkit.required")
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
        }
        .accessibilityIdentifier("clip-cloud-storage-status")
        .confirmationDialog(Text(verbatim: language.localized("sync.consent.title")), isPresented: Binding(get: { controller.pendingAccount != nil }, set: { if !$0 { controller.cancelEnrollment() } }), titleVisibility: .visible) {
            Button { controller.approveEnrollment(store: store) } label: { Text(verbatim: language.localized("sync.consent.confirm")) }
                .accessibilityIdentifier("clip-sync-confirm")
            Button(role: .cancel) { controller.cancelEnrollment() } label: { Text(verbatim: language.localized("common.cancel")) }
        } message: {
            Text(verbatim: language.localized("sync.consent.description"))
        }
    }
}
