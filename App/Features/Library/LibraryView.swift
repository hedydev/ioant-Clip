import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject private var language: LanguagePreferences
    @State private var selected: UUID?
    @State private var loaded: (id: UUID, note: Note?)?
    @State private var copiedID: UUID?
    @AppStorage("ioant.clip.library.plainPreview.v1") private var plainPreview = false
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var checked = Set<UUID>()
    @State private var selecting = false
    @AppStorage("ioant.clip.library.search.v1") private var query = ""
    @State private var importing = false
    @State private var appSettings = false
    @State private var storageSettings = false
    @State private var editingVisibleTags = false
    @State private var draftVisibleTags = Set<String>()
    @AppStorage("ioant.clip.library.visibleTags.v1") private var savedVisibleTags = ""
    @State private var sheetParentSize = PresentationMetrics.mainDefault
    @State private var editing: Note?
    @State private var confirmation: Confirmation?
    @AppStorage("ioant.clip.library.filter.v1") private var savedFilter = "all"
    private var tagFilter: TagFilter {
        get { TagFilter(preference: savedFilter) }
        nonmutating set { savedFilter = newValue.preference }
    }
    private var filterBinding: Binding<TagFilter> {
        Binding(get: { tagFilter }, set: { tagFilter = $0 })
    }
    enum Confirmation {
        case delete(Set<UUID>)
        case merge(Set<UUID>)

        var title: Text {
            switch self {
            case .delete(let ids): Text("library.delete.confirm \(ids.count)")
            case .merge(let ids): Text("library.merge.confirm \(ids.count)")
            }
        }
    }

    private var presentingConfirmation: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private struct DetailRequest: Equatable {
        let id: UUID?
        let revision: Int
    }

    private var detailRequest: DetailRequest {
        DetailRequest(id: selected, revision: store.listRevision)
    }

    var current: Note? { loaded?.id == selected ? loaded?.note : nil }
    var tags: [String] { store.allTags }
    private var visibleTags: [String] { VisibleLibraryTags.resolve(savedVisibleTags, available: tags) }
    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            LibrarySidebar(selected: $selected, compactColumn: $compactColumn, checked: $checked, selecting: $selecting, query: $query, appSettings: $appSettings, storageSettings: $storageSettings, requestConfirmation: { confirmation = $0 }, tagFilter: filterBinding, visibleTags: visibleTags, editVisibleTags: {
                draftVisibleTags = Set(visibleTags.map(TagColor.key))
                editingVisibleTags = true
            })
        } detail: {
            ClipDetailView(current: current, loadingNote: selected != nil && loaded?.id != selected, sheetParentSize: sheetParentSize, tags: tags, plainPreview: $plainPreview, copiedID: $copiedID, editing: $editing, requestDelete: { confirmation = .delete([$0]) }, importing: $importing, paste: paste)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let issue = store.captureInboxIssue {
                HStack(alignment: .top, spacing: LayoutMetrics.small) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(verbatim: language.localized(issue))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(LayoutMetrics.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .accessibilityIdentifier("clip-inbox-warning")
            }
        }
        .background { GeometryReader { geometry in
            Color.clear.preference(key: SheetParentSizeKey.self, value: geometry.size)
        } }
        .onPreferenceChange(SheetParentSizeKey.self) { size in
            if size.width > 0 && size.height > 0 { sheetParentSize = size }
        }
        .task(id: detailRequest) { [request = detailRequest] in
            guard let id = request.id else {
                if !Task.isCancelled { loaded = nil }
                return
            }
            do {
                let note = try await store.loadNote(id)
                guard !Task.isCancelled, request == detailRequest else { return }
                loaded = (id, note)
            } catch {
                guard !Task.isCancelled, request == detailRequest else { return }
                loaded = (id, nil)
                store.error = LibraryIssue(error)
            }
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
        .sheet(isPresented: $editingVisibleTags) {
            ClipSheet(title: "tags.display", parentSize: sheetParentSize, showsCancel: true, onConfirm: {
                savedVisibleTags = VisibleLibraryTags.preference(for: draftVisibleTags.intersection(tags.map(TagColor.key)))
                return true
            }) {
                LibraryVisibleTagsEditor(selected: $draftVisibleTags)
            }
        }
        .sheet(item: $editing) { note in
            EditClipView(note: note, store: store, parentSize: sheetParentSize) { title, tags, colors in
                let saved: Bool? = store.change { library in
                    library.update(note.id, title: title, tags: tags)
                    for (tag, color) in colors { library.setColor(color, for: tag) }
                    return true
                }
                return saved == true
            }
        }
        .onChange(of: tags, initial: true) { _, available in
            if editingVisibleTags { draftVisibleTags.formIntersection(available.map(TagColor.key)) }
            if case .tag(let tag) = tagFilter, !available.contains(where: { TagColor.key($0) == TagColor.key(tag) }) { tagFilter = .all }
        }
        .confirmationDialog(confirmation?.title ?? Text(""), isPresented: presentingConfirmation,
                            titleVisibility: .visible, presenting: confirmation) { action in
            switch action {
            case .delete(let ids):
                Button("common.delete", role: .destructive) { delete(ids) }
            case .merge(let ids):
                Button("library.merge") { merge(ids) }
            }
            Button("common.cancel", role: .cancel) { confirmation = nil }
        } message: { action in
            if case .merge = action { Text("library.merge.createsNew") }
        }
        .alert("ioant-Clip", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("common.ok") { store.error = nil } } message: { if let issue = store.error { Text(LocalizedStringKey(issue.key)); if let detail = issue.detail { Text(verbatim: detail) } } }
    }
    private func delete(_ ids: Set<UUID>) {
        guard store.change({ $0.delete(ids) }) != nil else { return }
        if let selected, ids.contains(selected) {
            self.selected = nil
            compactColumn = .sidebar
        }
        checked.subtract(ids)
    }

    private func merge(_ ids: Set<UUID>) {
        guard let id = store.change({ $0.merge(ids) }) ?? nil else { return }
        selected = id
        compactColumn = .detail
        selecting = false
        checked.removeAll()
    }

    func paste() {
        guard let part = Clipboard.read(), !part.isEmpty else { store.error = LibraryIssue("error.clipboard.empty"); return }
        if let id = store.change({ $0.add(part) }) ?? nil { selected = id; compactColumn = .detail; tagFilter = .all; query = "" }
    }
}

