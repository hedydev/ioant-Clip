import SwiftUI

struct LocalStorageSection: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var language: LanguagePreferences
    @State private var expanded = false

    var body: some View {
        let url = store.url
        ModalSection(title: "sync.storage.local") {
            StorageUsageRow(label: "sync.usage.local", revision: store.listRevision) {
                try StorageUsage.localBytes(libraryURL: url)
            }
            DisclosureGroup(isExpanded: $expanded) {
                if expanded {
                    StorageContentUsageRows(libraryURL: url, revision: store.listRevision)
                    ModalDescription(key: "sync.usage.explanation")
                }
            } label: { Text(verbatim: language.localized("sync.usage.details")) }
        }
    }
}

struct StorageUsageRow<Revision: Equatable>: View {
    @EnvironmentObject private var language: LanguagePreferences
    @State private var bytes: Int64?
    @State private var loading = true
    let label: String
    let revision: Revision
    let read: @Sendable () throws -> Int64?

    var body: some View {
        LabeledContent {
            if loading {
                ProgressView().controlSize(.small)
            } else if let bytes {
                Text(bytes, format: .byteCount(style: .file)).monospacedDigit()
            } else {
                Text(verbatim: language.localized("sync.usage.unavailable")).foregroundStyle(.secondary)
            }
        } label: {
            Text(verbatim: language.localized(label))
        }
        .task(id: revision) {
            let result = await storageRead(read) ?? nil
            guard !Task.isCancelled else { return }
            bytes = result
            loading = false
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
