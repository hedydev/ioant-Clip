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
    let requestConfirmation: (LibraryView.Confirmation) -> Void
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
    @State private var moreTask: Task<Void, Never>?
    private struct PageRequest: Equatable {
        let revision: Int
        let query: String
        let tagFilter: TagFilter
    }
    private var request: PageRequest {
        PageRequest(revision: store.listRevision, query: query, tagFilter: tagFilter)
    }
    private func reload(_ key: PageRequest) async {
        cancelPagination()
        do {
            if key.query != loadedRequest?.query && !key.query.isEmpty {
                try await Task.sleep(for: .milliseconds(160))
            }
            let page = try await store.loadPage(query: key.query, filter: key.tagFilter, after: nil)
            guard !Task.isCancelled, request == key else { return }
            total = page.total ?? page.rows.count
            rows = page.rows
            loadedRequest = key
        } catch {
            guard !Task.isCancelled, request == key else { return }
            store.error = LibraryIssue(error)
            rows = []
            total = 0
            loadedRequest = key
        }
    }

    private func cancelPagination() {
        moreTask?.cancel()
        moreTask = nil
    }

    private func loadMore(after id: UUID) {
        let key = request
        guard moreTask == nil, loadedRequest == key, rows.count < total,
              let cursor = rows.last, cursor.id == id else { return }
        moreTask = Task {
            defer { if !Task.isCancelled { moreTask = nil } }
            do {
                let page = try await store.loadPage(query: key.query, filter: key.tagFilter, after: cursor)
                guard !Task.isCancelled, request == key, rows.last?.id == cursor.id else { return }
                if page.rows.isEmpty { total = rows.count }
                else { rows += page.rows }
            } catch {
                guard !Task.isCancelled, request == key else { return }
                store.error = LibraryIssue(error)
            }
        }
    }
    private var clipRowInsets: EdgeInsets? {
        #if os(macOS)
        EdgeInsets(top: 0, leading: LayoutMetrics.large, bottom: 0, trailing: LayoutMetrics.large)
        #else
        nil
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryFilters(store: store, selection: tagFilter, visibleTags: visibleTags, compact: compact,
                           select: applyFilter, edit: editVisibleTags)
            Divider()
            collectionHeader
            List {
                if rows.isEmpty && loadedRequest != request {
                    ProgressView().controlSize(.small)
                } else if rows.isEmpty {
                    Label(query.isEmpty ? LocalizedStringKey("library.noClips") : LocalizedStringKey("library.noResults"), systemImage: query.isEmpty ? "tray" : "magnifyingglass")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, LayoutMetrics.small)
                        .listRowInsets(clipRowInsets)
                }
                ForEach(rows) { note in
                    Button { open(note) } label: {
                        ClipListRow(note: note, selecting: selecting, checked: checked.contains(note.id), color: store.color(for:))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(clipRowInsets)
                    .listRowBackground((selecting ? checked.contains(note.id) : selected == note.id) ? theme.selectedRow : Color.clear)
                    .accessibilityAddTraits((selecting ? checked.contains(note.id) : selected == note.id) ? [.isSelected] : [])
                    .onAppear { loadMore(after: note.id) }
                }
            }
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
            .accessibilityIdentifier("clip-list")
        }
        .task(id: request) { [key = request] in await reload(key) }
        .onDisappear { cancelPagination() }
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
                LibrarySelectionBar(count: checked.count, merge: {
                    requestConfirmation(.merge(checked))
                }, delete: {
                    requestConfirmation(.delete(checked))
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
        guard filter != .all, let id = selected else { return }
        Task {
            do {
                let matches = try await store.matchesFilter(filter, note: id)
                guard !matches, selected == id, tagFilter == filter else { return }
                selected = nil
            } catch {
                guard !Task.isCancelled, selected == id, tagFilter == filter else { return }
                store.error = LibraryIssue(error)
            }
        }
    }
}
