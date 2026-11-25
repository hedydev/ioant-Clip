import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var selected: UUID?
    @Binding var compactColumn: NavigationSplitViewColumn
    @Binding var checked: Set<UUID>
    @Binding var selecting: Bool
    @Binding var query: String
    @Binding var importing: Bool
    @Binding var syncSettings: Bool
    @Binding var appSettings: Bool
    @Binding var deleting: Set<UUID>
    @Binding var confirmDelete: Bool
    @Binding var tagFilter: TagFilter
    let paste: () -> Void
    var current: Note? { store.library.notes.first { $0.id == selected } }
    var tags: [String] { store.library.allTags }
    var filtered: [Note] { store.library.filtered(query: query, filter: tagFilter) }
    var body: some View {
            List {
                Section("tags.title") {
                    filterRow("library.all", icon: "tray.full", filter: .all, count: store.library.notes.count)
                    filterRow("library.untagged", icon: "tag.slash", filter: .untagged, count: store.library.notes.filter { $0.tags.isEmpty }.count)
                    ForEach(tags, id: \.self) { tag in
                        filterRow(tag, color: store.library.color(for: tag), filter: .tag(tag), count: store.library.notes.filter { TagFilter.tag(tag).includes($0) }.count)
                    }
                }
                Section("library.count \(filtered.count)") {
                    ForEach(filtered) { note in
                        Button { if selecting { if checked.contains(note.id) { checked.remove(note.id) } else { checked.insert(note.id) } } else { selected = note.id; compactColumn = .detail } } label: {
                            HStack(alignment: .top, spacing: 9) {
                                if selecting { Image(systemName: checked.contains(note.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(note.title).font(.headline).lineLimit(2)
                                    Text(note.parts.first?.text ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    Text(note.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                                    if !note.tags.isEmpty { TagChipRow(tags: note.tags, color: store.library.color(for:)) }
                                }
                                Spacer()
                            }.padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain).listRowBackground(selected == note.id ? Color.accentColor.opacity(0.12) : Color.clear)
                    }
                }
            }.navigationTitle("ioant-Clip").searchable(text: $query, prompt: Text("library.search"))
                .toolbar {
                    ToolbarItemGroup {
                        Button { appSettings = true } label: { Label("settings.title", systemImage: "gearshape") }
                        Button { syncSettings = true } label: { Label("sync.title", systemImage: "icloud") }
                        Button { selecting.toggle(); checked.removeAll() } label: { Label(LocalizedStringKey(selecting ? "common.done" : "common.select"), systemImage: selecting ? "checkmark" : "checkmark.circle") }
                    }
                }
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 380)
                #endif
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 8) {
                        pasteButton
                        Button { importing = true } label: {
                            Label("library.import", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(.regularMaterial)
                }
                .safeAreaInset(edge: .bottom) {
                    if selecting { HStack { Text("library.selected \(checked.count)"); Spacer(); Button("Merge clips") { if let id = store.change({ $0.merge(checked) }) ?? nil { selected = id; compactColumn = .detail; selecting = false; checked.removeAll() } }.disabled(checked.count < 2); Button(role: .destructive) { deleting = checked; confirmDelete = true } label: { Image(systemName: "trash").accessibilityLabel(Text("common.delete")) }.disabled(checked.isEmpty) }.padding().background(.regularMaterial) }
                }
    }
    private func filterRow(_ name: String, icon: String = "tag.fill", color: TagColor? = nil, filter: TagFilter, count: Int) -> some View {
        Button {
            tagFilter = filter
            checked.removeAll()
            if let note = current, !filter.includes(note) { selected = nil }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).foregroundStyle(color?.swiftUIColor ?? Color.secondary)
                filterLabel(name, filter: filter).lineLimit(1)
                Spacer()
                Text(count, format: .number).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(tagFilter == filter ? Color.accentColor.opacity(0.15) : Color.clear)
        .accessibilityAddTraits(tagFilter == filter ? [.isSelected] : [])
    }
    private func filterLabel(_ name: String, filter: TagFilter) -> Text {
        if case .tag = filter { return Text(verbatim: name) }
        return Text(LocalizedStringKey(name))
    }
    private var pasteButton: some View {
        Button(action: paste) {
            Label("library.paste", systemImage: "doc.on.clipboard")
                .frame(maxWidth: .infinity)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut("v", modifiers: .command)
        .accessibilityIdentifier("paste-new-note")
        .help("library.empty.title")
    }
}
