import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var selected: UUID?
    @State private var copiedID: UUID?
    @AppStorage("ioant.clip.library.plainPreview.v1") private var plainPreview = false
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var checked = Set<UUID>()
    @State private var selecting = false
    @AppStorage("ioant.clip.library.search.v1") private var query = ""
    @State private var importing = false
    @State private var appSettings = false
    @State private var storageSettings = false
    @State private var sheetParentSize = PresentationMetrics.mainDefault
    @State private var editing: Note?
    @State private var deleting = Set<UUID>()
    @State private var confirmDelete = false
    @AppStorage("ioant.clip.library.filter.v1") private var savedFilter = "all"
    private var tagFilter: TagFilter {
        get { TagFilter(preference: savedFilter) }
        nonmutating set { savedFilter = newValue.preference }
    }
    private var filterBinding: Binding<TagFilter> {
        Binding(get: { tagFilter }, set: { tagFilter = $0 })
    }
    var current: Note? { store.library.notes.first { $0.id == selected } }
    var tags: [String] { store.library.allTags }
    var filtered: [Note] { store.library.filtered(query: query, filter: tagFilter) }
    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            LibrarySidebar(selected: $selected, compactColumn: $compactColumn, checked: $checked, selecting: $selecting, query: $query, importing: $importing, appSettings: $appSettings, storageSettings: $storageSettings, deleting: $deleting, confirmDelete: $confirmDelete, tagFilter: filterBinding, paste: paste)
        } detail: {
            ClipDetailView(current: current, tags: tags, plainPreview: $plainPreview, copiedID: $copiedID, editing: $editing, deleting: $deleting, confirmDelete: $confirmDelete, importing: $importing, paste: paste)
        }
        .background { GeometryReader { geometry in
            Color.clear.preference(key: SheetParentSizeKey.self, value: geometry.size)
        } }
        .onPreferenceChange(SheetParentSizeKey.self) { size in
            if size.width > 0 && size.height > 0 { sheetParentSize = size }
        }
        .onChange(of: selected) { _, _ in copiedID = nil }
        .onChange(of: store.lastIncoming) { _, id in
            if let id, !selecting { selected = id; compactColumn = .detail; tagFilter = .all; query = "" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): if let id = store.importFile(url) { selected = id; compactColumn = .detail; tagFilter = .all; query = "" }; case .failure(let error): store.error = LibraryIssue(error) }
        }
        .sheet(isPresented: $appSettings) {
            ClipSheet(title: "settings.title", size: .large, parentSize: sheetParentSize) {
                AppSettingsView()
            }
        }
        .sheet(isPresented: $storageSettings) {
            ClipSheet(title: "sync.title", size: .large, parentSize: sheetParentSize) {
                SyncSettingsView()
            }
        }
        .sheet(item: $editing) { note in
            EditClipView(note: note, library: store.library, parentSize: sheetParentSize) { title, tags, colors in
                let saved: Bool? = store.change { library in
                    library.update(note.id, title: title, tags: tags)
                    for (tag, color) in colors { library.setColor(color, for: tag) }
                    return true
                }
                return saved == true
            }
        }
        .onChange(of: tags, initial: true) { _, available in
            if case .tag(let tag) = tagFilter, !available.contains(where: { TagColor.key($0) == TagColor.key(tag) }) { tagFilter = .all }
        }
        .confirmationDialog("library.delete.confirm \(deleting.count)", isPresented: $confirmDelete, titleVisibility: .visible) { Button("common.delete", role: .destructive) { if store.change({ $0.delete(deleting) }) != nil { if let selected, deleting.contains(selected) { self.selected = nil; compactColumn = .sidebar }; checked.subtract(deleting) }; deleting.removeAll() } }
        .alert("ioant-Clip", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("common.ok") { store.error = nil } } message: { if let issue = store.error { Text(LocalizedStringKey(issue.key)); if let detail = issue.detail { Text(verbatim: detail) } } }
    }
    func paste() {
        guard let part = Clipboard.read(), !part.isEmpty else { store.error = LibraryIssue("error.clipboard.empty"); return }
        if let id = store.change({ $0.add(part) }) ?? nil { selected = id; compactColumn = .detail; tagFilter = .all; query = "" }
    }
}

