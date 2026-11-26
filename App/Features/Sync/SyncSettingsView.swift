import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var language: LanguagePreferences
    @State private var pending: SyncRevision?
    private var journal: SyncJournal? { store.library.syncJournal }
    var body: some View {
        ModalScrollPage {
                ModalSection(title: "sync.storage") {
                    CloudStorageStatusRow()
                    ModalDescription(key: store.enrollment == nil ? "sync.local.description" : "sync.bound.description")
                }
                ModalSection(title: "sync.providers") {
                    CloudKitSettingsSection()
                    Divider()
                    provider("Google Drive", icon: "externaldrive", status: "sync.google.required")
                }
                ModalSection(title: "sync.history") {
                    LabeledContent { Text(journal?.revisions.count ?? 0, format: .number) } label: { Text(verbatim: language.localized("sync.revisions")) }
                    LabeledContent { Text(journal?.conflictKeys.count ?? 0, format: .number) } label: { Text(verbatim: language.localized("sync.conflicts")) }
                    ModalDescription(key: store.enrollment == nil ? "sync.history.description" : "sync.history.cloudDescription")
                }
                if let journal {
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
            .navigationTitle(Text(verbatim: language.localized("sync.title")))
            .confirmationDialog(Text(verbatim: language.localized("sync.conflict.confirm")), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button {
                    if let revision = pending { store.resolveConflict(revision.key, revision: revision.id) }
                    pending = nil
                } label: { Text(verbatim: language.localized("sync.conflict.keepSelected")) }
                Button(role: .cancel) { pending = nil } label: { Text(verbatim: language.localized("common.cancel")) }
            }
    }
    private func provider(_ name: String, icon: String, status: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                providerDetails(name, icon: icon, status: status)
                Spacer(minLength: LayoutMetrics.small)
                Text(verbatim: language.localized("sync.disconnected")).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: LayoutMetrics.small) {
                providerDetails(name, icon: icon, status: status)
                Text(verbatim: language.localized("sync.disconnected")).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
    private func providerDetails(_ name: String, icon: String, status: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(verbatim: language.localized(status)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
