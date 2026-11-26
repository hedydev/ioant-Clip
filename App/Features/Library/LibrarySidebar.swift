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
    private var compact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }
    private var filtered: [Note] { store.library.filtered(query: query, filter: tagFilter) }
    var body: some View {
        List {
            if !compact {
                LibraryFilters(library: store.library, selection: tagFilter, compact: false, select: applyFilter)
            }
            Section("library.count \(filtered.count)") {
                if filtered.isEmpty {
                    Label(query.isEmpty ? LocalizedStringKey("library.noClips") : LocalizedStringKey("library.noResults"), systemImage: query.isEmpty ? "tray" : "magnifyingglass")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, LayoutMetrics.small)
                }
                ForEach(filtered) { note in
                    Button { open(note) } label: {
                        ClipListRow(note: note, selecting: selecting, checked: checked.contains(note.id), color: store.library.color(for:))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground((selecting ? checked.contains(note.id) : selected == note.id) ? theme.selectedRow : Color.clear)
                    .accessibilityAddTraits((selecting ? checked.contains(note.id) : selected == note.id) ? [.isSelected] : [])
                }
            }
        }
        .navigationTitle(ClipPreferencesScope.windowTitle)
        .searchable(text: $query, prompt: Text("library.search"))
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .toolbar {
            ToolbarItemGroup {
                CloudStorageToolbarButton { storageSettings = true }
                Button { appSettings = true } label: {
                    Label("settings.title", systemImage: "gearshape")
                        .foregroundStyle(theme.action)
                }
                    .accessibilityIdentifier("clip-settings")
                Button { selecting.toggle(); checked.removeAll() } label: {
                    Label(LocalizedStringKey(selecting ? "common.done" : "common.select"), systemImage: selecting ? "checkmark" : "checkmark.circle")
                        .foregroundStyle(theme.action)
                }
                .accessibilityIdentifier("clip-select")
            }
        }
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        #endif
        .safeAreaInset(edge: .top, spacing: 0) {
            if compact {
                LibraryFilters(library: store.library, selection: tagFilter, compact: true, select: applyFilter)
                    .padding(LayoutMetrics.medium)
                    .background(.regularMaterial)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                LibrarySelectionBar(count: checked.count, merge: merge, delete: {
                    deleting = checked
                    confirmDelete = true
                })
            }
        }
    }
    private func open(_ note: Note) {
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
        if let note = store.library.notes.first(where: { $0.id == selected }), !filter.includes(note) { selected = nil }
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
