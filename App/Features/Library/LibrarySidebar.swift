import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.clipTheme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Binding var selected: UUID?
    @Binding var compactColumn: NavigationSplitViewColumn
    @Binding var checked: Set<UUID>
    @Binding var selecting: Bool
    @Binding var query: String
    @Binding var appSettings: Bool
    @Binding var storageSettings: Bool
    @Binding var deleting: Set<UUID>
    @Binding var confirmDelete: Bool
    @Binding var tagFilter: TagFilter
    let visibleTags: [String]
    let editVisibleTags: () -> Void
    private var compact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }
    @State private var rows: [SQLiteNoteRepository.Row] = []
    @State private var total = 0
    @State private var loadedRequest: PageRequest?
    private struct PageRequest: Equatable {
        let revision: Int
        let query: String
        let tagFilter: TagFilter
    }
    private var request: PageRequest {
        PageRequest(revision: store.listRevision, query: query, tagFilter: tagFilter)
    }
    private func reload() {
        let key = request
        total = store.count(query: key.query, filter: key.tagFilter)
        rows = store.page(query: key.query, filter: key.tagFilter, after: nil)
        loadedRequest = key
    }
    private func loadMore(after id: UUID) {
        let key = request
        guard loadedRequest == key, rows.count < total, let cursor = rows.last, cursor.id == id else { return }
        rows += store.page(query: key.query, filter: key.tagFilter, after: cursor)
    }
    var body: some View {
        VStack(spacing: 0) {
            LibraryFilters(store: store, selection: tagFilter, visibleTags: visibleTags, compact: compact,
                           select: applyFilter, edit: editVisibleTags)
            Divider()
            collectionHeader
            List {
                if rows.isEmpty {
                    Label(query.isEmpty ? LocalizedStringKey("library.noClips") : LocalizedStringKey("library.noResults"), systemImage: query.isEmpty ? "tray" : "magnifyingglass")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, LayoutMetrics.small)
                }
                ForEach(rows) { note in
                    Button { open(note) } label: {
                        ClipListRow(note: note, selecting: selecting, checked: checked.contains(note.id), color: store.color(for:))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground((selecting ? checked.contains(note.id) : selected == note.id) ? theme.selectedRow : Color.clear)
                    .accessibilityAddTraits((selecting ? checked.contains(note.id) : selected == note.id) ? [.isSelected] : [])
                    .onAppear { loadMore(after: note.id) }
                }
            }
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
            .accessibilityIdentifier("clip-list")
        }
        .onChange(of: request, initial: true) { _, _ in reload() }
        .navigationTitle(ClipPreferencesScope.windowTitle)
        .searchable(text: $query, prompt: Text("library.search"))
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup {
                CloudStorageToolbarButton { storageSettings = true }
                Button { appSettings = true } label: {
                    Label("settings.title", systemImage: "gearshape")
                        .foregroundStyle(theme.action)
                }
                    .accessibilityIdentifier("clip-settings")
            }
        }
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        #endif
    }

    private var collectionHeader: some View {
        HStack(spacing: LayoutMetrics.small) {
            if selecting {
                Text("library.selected \(checked.count)")
            } else {
                Text("library.count \(total)")
            }
            Spacer(minLength: 0)
            if selecting {
                LibrarySelectionBar(count: checked.count, merge: merge, delete: {
                    deleting = checked
                    confirmDelete = true
                }, done: toggleSelection)
            } else {
                Button(action: toggleSelection) {
                    Label("common.edit", systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help(Text("common.edit"))
                .accessibilityIdentifier("clip-select")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, LayoutMetrics.medium)
        .padding(.vertical, LayoutMetrics.small)
    }

    private func toggleSelection() {
        selecting.toggle()
        checked.removeAll()
    }

    private func open(_ note: SQLiteNoteRepository.Row) {
        if selecting {
            if checked.contains(note.id) { checked.remove(note.id) } else { checked.insert(note.id) }
        } else {
            selected = note.id
            compactColumn = .detail
        }
    }
    private func applyFilter(_ filter: TagFilter) {
        tagFilter = filter
        checked.removeAll()
        if let note = store.note(selected), !filter.includes(note) { selected = nil }
    }
    private func merge() {
        if let id = store.change({ $0.merge(checked) }) ?? nil {
            selected = id
            compactColumn = .detail
            selecting = false
            checked.removeAll()
        }
    }
}
