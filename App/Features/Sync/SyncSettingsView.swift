import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var language: LanguagePreferences
    @State private var pending: SyncRevision?
    var body: some View {
        ModalScrollPage {
            LocalStorageSection()
            ModalSection(title: "sync.icloud") {
                CloudKitSettingsSection()
                if store.enrollment != nil {
                    DisclosureGroup {
                        LabeledContent {
                            Text(store.revisionCount, format: .number)
                        } label: { Text(verbatim: language.localized("sync.revisions")) }
                        LabeledContent {
                            Text(store.syncConflictCount, format: .number)
                        } label: { Text(verbatim: language.localized("sync.conflicts")) }
                        ModalDescription(key: "sync.history.cloudDescription")
                        ModalDescription(key: "sync.usage.remoteDetails")
                    } label: { Text(verbatim: language.localized("sync.history")) }
                }
                if store.hasConflicts, let journal = store.library.syncJournal {
                    ForEach(Array(journal.conflictKeys).sorted(by: { String(describing: $0) < String(describing: $1) }), id: \.self) { key in
                        ModalSection(title: "sync.conflict.versions") {
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
                                        Label { Text(verbatim: language.localized("sync.conflict.deleted")) } icon: { Image(systemName: "trash") }.foregroundStyle(.secondary)
                                    }
                                    Button { pending = revision } label: { Text(verbatim: language.localized("sync.conflict.keep")) }.buttonStyle(.bordered)
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(Text(verbatim: language.localized("sync.conflict.confirm")), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button {
                if let revision = pending { store.resolveConflict(revision.key, revision: revision.id) }
                pending = nil
            } label: { Text(verbatim: language.localized("sync.conflict.keepSelected")) }
            Button(role: .cancel) { pending = nil } label: { Text(verbatim: language.localized("common.cancel")) }
        }
    }
}
