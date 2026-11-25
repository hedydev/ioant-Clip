import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var pending: SyncRevision?
    private var journal: SyncJournal? { store.library.syncJournal }
    var body: some View {
        NavigationStack {
            List {
                Section("Storage") {
                    Label("Local only", systemImage: "checkmark.circle.fill")
                    Text("All clips stay on this device. Cloud providers are not connected.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Cloud providers") {
                    provider("iCloud", icon: "icloud", status: "Requires signed CloudKit configuration")
                    provider("Google Drive", icon: "externaldrive", status: "Requires Google OAuth configuration")
                }
                Section("Local sync history") {
                    LabeledContent("Recorded revisions", value: (journal?.revisions.count ?? 0).formatted())
                    LabeledContent("Conflicts", value: (journal?.conflictKeys.count ?? 0).formatted())
                    Text("Version history is local. Nothing has been uploaded.").font(.caption).foregroundStyle(.secondary)
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
                                        Label("Deleted version", systemImage: "trash").foregroundStyle(.secondary)
                                    }
                                    Button("Keep this version") { pending = revision }.buttonStyle(.bordered)
                                }.padding(.vertical, 4)
                            }
                        } header: { Text("Conflicting versions") }
                    }
                }
            }
            .navigationTitle("Cloud sync")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Resolve this conflict?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button("Keep selected version") {
                    if let revision = pending { store.resolveConflict(revision.key, revision: revision.id) }
                    pending = nil
                }
                Button("Cancel", role: .cancel) { pending = nil }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 540)
        #endif
    }
    private func provider(_ name: String, icon: String, status: LocalizedStringKey) -> some View {
        HStack {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Not connected").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
