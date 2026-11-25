import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var pending: SyncRevision?
    private var journal: SyncJournal? { store.library.syncJournal }
    var body: some View {
        List {
                Section("sync.storage") {
                    Label("sync.local", systemImage: "checkmark.circle.fill")
                    Text("sync.local.description").font(.caption).foregroundStyle(.secondary)
                }
                Section("sync.providers") {
                    provider("iCloud", icon: "icloud", status: "sync.cloudkit.required")
                    provider("Google Drive", icon: "externaldrive", status: "sync.google.required")
                }
                Section("sync.history") {
                    LabeledContent { Text(journal?.revisions.count ?? 0, format: .number) } label: { Text("sync.revisions") }
                    LabeledContent { Text(journal?.conflictKeys.count ?? 0, format: .number) } label: { Text("sync.conflicts") }
                    Text("sync.history.description").font(.caption).foregroundStyle(.secondary)
                }
                if let journal {
                    ForEach(Array(journal.conflictKeys).sorted(by: { String(describing: $0) < String(describing: $1) }), id: \.self) { key in
                        Section {
                            ForEach(journal.heads(for: key), id: \.id) { revision in
                                VStack(alignment: .leading, spacing: 6) {
                                    switch revision.value {
                                    case .note(let note):
                                        Text(note.title).font(.headline)
                                        Text(note.plainText).font(.caption).lineLimit(8).textSelection(.enabled)
                                        if !note.tags.isEmpty { Text(note.tags.joined(separator: ", ")).font(.caption) }
                                    case .tagColor(let color):
                                        Label(color.label, systemImage: "circle.fill").foregroundStyle(color.swiftUIColor)
                                    case .deleted:
                                        Label("sync.conflict.deleted", systemImage: "trash").foregroundStyle(.secondary)
                                    }
                                    Button("sync.conflict.keep") { pending = revision }.buttonStyle(.bordered)
                                }.padding(.vertical, 4)
                            }
                        } header: { Text("sync.conflict.versions") }
                    }
                }
            }
            .navigationTitle("sync.title")
            .confirmationDialog("sync.conflict.confirm", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button("sync.conflict.keepSelected") {
                    if let revision = pending { store.resolveConflict(revision.key, revision: revision.id) }
                    pending = nil
                }
                Button("common.cancel", role: .cancel) { pending = nil }
            }
    }
    private func provider(_ name: String, icon: String, status: LocalizedStringKey) -> some View {
        HStack {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("sync.disconnected").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
