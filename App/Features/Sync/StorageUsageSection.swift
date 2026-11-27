import SwiftUI

struct StorageUsageSection: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var language: LanguagePreferences
    @EnvironmentObject private var controller: CloudSyncController
    @State private var usage: StorageUsage?
    @State private var expanded = false

    private struct Refresh: Equatable {
        let libraryRevision: Int
        let lastSync: Date?
    }

    var body: some View {
        ModalSection(title: "sync.usage.title") {
            LabeledContent {
                if let usage {
                    size(usage.localBytes)
                } else {
                    ProgressView().controlSize(.small)
                }
            } label: { title("sync.usage.local") }
            LabeledContent {
                if store.enrollment == nil {
                    title("sync.disconnected").foregroundStyle(.secondary)
                } else {
                    size(usage?.estimatedSyncBytes)
                }
            } label: { title("sync.usage.remote") }

            DisclosureGroup(isExpanded: $expanded) {
                if expanded {
                    StorageContentUsageRows(libraryURL: store.url, revision: store.listRevision)
                    ModalDescription(key: "sync.usage.explanation")
                    if store.enrollment != nil {
                        ModalDescription(key: "sync.usage.remoteDetails")
                    }
                    Link(destination: URL(string: "https://support.apple.com/108922")!) {
                        title("sync.usage.help")
                    }
                }
            } label: { title("sync.usage.details") }
        }
        .task(id: Refresh(libraryRevision: store.listRevision, lastSync: controller.lastSuccess)) {
            let url = store.url
            let account = store.enrollment?.account
            let zone = CloudKitReviewConfiguration.zoneName
            let result = await storageRead { try StorageUsage.read(libraryURL: url, account: account, zone: zone) }
            guard !Task.isCancelled else { return }
            usage = result ?? StorageUsage(localBytes: nil, estimatedSyncBytes: nil)
        }
    }

    private func title(_ key: String) -> Text {
        Text(verbatim: language.localized(key))
    }

    @ViewBuilder private func size(_ bytes: Int64?) -> some View {
        if let bytes {
            Text(bytes, format: .byteCount(style: .file)).monospacedDigit()
        } else {
            title("sync.usage.unavailable").foregroundStyle(.secondary)
        }
    }
}

private struct StorageContentUsageRows: View {
    @EnvironmentObject private var language: LanguagePreferences
    @State private var usage: StorageContentUsage?
    @State private var failed = false
    let libraryURL: URL
    let revision: Int

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.small) {
            if let usage {
                row("sync.usage.documents", usage.documentBytes)
                row("sync.usage.images", usage.imageBytes)
                row("sync.usage.svg", usage.svgBytes)
                row("sync.usage.audio", usage.audioBytes)
                row("sync.usage.video", usage.videoBytes)
            } else if failed {
                Text(verbatim: language.localized("sync.usage.unavailable")).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: revision) {
            let url = libraryURL
            let result = await storageRead { try SQLiteNoteRepository.readStorageContentUsage(legacyURL: url) }
            guard !Task.isCancelled else { return }
            usage = result
            failed = result == nil
        }
    }

    private func row(_ key: String, _ bytes: Int64) -> some View {
        LabeledContent {
            Text(bytes, format: .byteCount(style: .file)).monospacedDigit()
        } label: {
            Text(verbatim: language.localized(key))
        }
    }
}

private func storageRead<Result: Sendable>(_ read: @escaping @Sendable () throws -> Result) async -> Result? {
    let worker = Task.detached(priority: .utility) { try read() }
    return await withTaskCancellationHandler {
        try? await worker.value
    } onCancel: {
        worker.cancel()
    }
}
