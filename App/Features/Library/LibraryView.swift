import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var selected: UUID?
    @State private var copiedID: UUID?
    @State private var plainPreview = false
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var checked = Set<UUID>()
    @State private var selecting = false
    @State private var query = ""
    @State private var importing = false
    @State private var syncSettings = false
    @State private var editing: Note?
    @State private var deleting = Set<UUID>()
    @State private var confirmDelete = false
    @State private var tagFilter: TagFilter = .all
    var current: Note? { store.library.notes.first { $0.id == selected } }
    var tags: [String] { store.library.allTags }
    var filtered: [Note] { store.library.filtered(query: query, filter: tagFilter) }
    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            LibrarySidebar(selected: $selected, compactColumn: $compactColumn, checked: $checked, selecting: $selecting, query: $query, importing: $importing, syncSettings: $syncSettings, deleting: $deleting, confirmDelete: $confirmDelete, tagFilter: $tagFilter, paste: paste)
        } detail: {
            ClipDetailView(current: current, tags: tags, plainPreview: $plainPreview, copiedID: $copiedID, editing: $editing, deleting: $deleting, confirmDelete: $confirmDelete, importing: $importing, paste: paste)
        }
        .onChange(of: selected) { _, _ in plainPreview = false; copiedID = nil }
        .onChange(of: store.lastIncoming) { _, id in
            if let id, !selecting { selected = id; compactColumn = .detail; tagFilter = .all; query = "" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): if let id = store.importFile(url) { selected = id; compactColumn = .detail; tagFilter = .all; query = "" }; case .failure(let error): store.error = error.localizedDescription }
        }
        .sheet(isPresented: $syncSettings) { SyncSettingsView().environmentObject(store) }
        .sheet(item: $editing) { note in
            EditClipView(note: note, library: store.library) { title, tags, colors in
                let saved: Bool? = store.change { library in
                    library.update(note.id, title: title, tags: tags)
                    for (tag, color) in colors { library.setColor(color, for: tag) }
                    return true
                }
                return saved == true
            }
        }
        .onChange(of: tags) { _, available in
            if case .tag(let tag) = tagFilter, !available.contains(where: { TagColor.key($0) == TagColor.key(tag) }) { tagFilter = .all }
        }
        .confirmationDialog("Delete \(deleting.count) clip(s)?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Delete", role: .destructive) { if store.change({ $0.delete(deleting) }) != nil { if let selected, deleting.contains(selected) { self.selected = nil; compactColumn = .sidebar }; checked.subtract(deleting) }; deleting.removeAll() } }
        .alert("ioant-Clip", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    func paste() {
        guard let part = Clipboard.read(), !part.isEmpty else { store.error = "No supported content in the clipboard."; return }
        if let id = store.change({ $0.add(part) }) ?? nil { selected = id; compactColumn = .detail; tagFilter = .all; query = "" }
    }
}

