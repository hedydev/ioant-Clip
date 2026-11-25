import SwiftUI
import UniformTypeIdentifiers
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor final class LibraryStore: ObservableObject {
    @Published private(set) var library = NoteLibrary()
    @Published var error: String?
    private let url = URL.applicationSupportDirectory.appending(path: "ioant-Note/notes.json")
    private var ready = false
    @Published private(set) var lastIncoming: UUID?
    private var reportedInboxFailures = Set<String>()
    init() {
        do {
            var loaded = try NoteLibrary.load(from: url)
            if loaded.syncJournal == nil {
                try loaded.initializeSyncJournal()
                try loaded.save(to: url)
            }
            library = loaded
            ready = true
        }
        catch { self.error = "Cannot open library. Existing data was not changed: \(error.localizedDescription)" }
    }
    @discardableResult func change<T>(_ mutation: (inout NoteLibrary) -> T) -> T? {
        guard ready else { error = "Library is unavailable."; return nil }
        var next = library; let result = mutation(&next)
        do {
            try next.recordLocalChanges(from: library)
            try next.save(to: url)
            library = next
            return result
        }
        catch { self.error = error.localizedDescription; return nil }
    }
    func resolveConflict(_ key: SyncKey, revision: UUID) {
        guard ready else { return }
        var next = library
        do {
            try next.resolveSyncConflict(key, choosing: revision)
            try next.save(to: url)
            library = next
        } catch { self.error = error.localizedDescription }
    }
    #if os(macOS)
    func receivePendingCaptures() {
        guard ready else { return }
        let inbox = url.deletingLastPathComponent().appending(path: "CaptureInbox")
        do {
            var next = library
            let result = try CaptureInbox.drain(directory: inbox, libraryURL: url, library: &next)
            if !result.imported.isEmpty { library = next }
            if let id = result.imported.last { lastIncoming = id }
            let newFailures = Set(result.failures).subtracting(reportedInboxFailures)
            if !newFailures.isEmpty { error = "Some incoming captures could not be imported. The files have been retained." }
            reportedInboxFailures = Set(result.failures)
        } catch {
            if reportedInboxFailures.insert("directory").inserted { self.error = "Cannot read incoming captures." }
        }
    }
    #endif
    func importFile(_ url: URL) -> UUID? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= WebCapture.maxBytes else { throw WebCapture.ImportError.tooLarge }
            let capture = try WebCapture.decode(Data(contentsOf: url))
            let id = change { $0.add(capture.part, title: capture.title) } ?? nil
            if capture.truncated == true, id != nil { error = "Imported capture; the extension reported truncated content." }
            return id
        } catch { self.error = error.localizedDescription; return nil }
    }
}

@MainActor enum Clipboard {
    static func read() -> NotePart? {
        #if os(macOS)
        let board = NSPasteboard.general
        let text = board.string(forType: .string) ?? ""
        var html = board.string(forType: .html)
        if html == nil, let rtf = board.data(forType: .rtf) { html = richHTML(rtf) }
        if let html, !html.isEmpty { return .init(html: html, text: text) }
        if let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { return .init(text: text, image: png, imageMIME: "image/png") }
        #else
        let board = UIPasteboard.general
        let text = board.string ?? ""
        var html = board.data(forPasteboardType: "public.html").flatMap { String(data: $0, encoding: .utf8) }
        if html == nil, let rtf = board.data(forPasteboardType: "public.rtf") { html = richHTML(rtf) }
        if let html, !html.isEmpty { return .init(html: html, text: text) }
        if let png = board.image?.pngData() { return .init(text: text, image: png, imageMIME: "image/png") }
        #endif
        return text.isEmpty ? nil : .init(text: text)
    }
    static func copy(_ note: Note) {
        let text = note.parts.map(\.text).joined(separator: "\n\n")
        let html = note.parts.map(\.renderedHTML).joined(separator: "\n<hr>\n")
        #if os(macOS)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(html, forType: .html)
        board.setString(text, forType: .string)
        #else
        UIPasteboard.general.setItems([["public.html": Data(html.utf8), "public.utf8-plain-text": text]])
        #endif
    }
    static func richHTML(_ data: Data) -> String? {
        guard let string = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil), let html = try? string.data(from: NSRange(location: 0, length: string.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) else { return nil }
        return String(data: html, encoding: .utf8)
    }
}

@main struct NoteApp: App {
    @StateObject private var store = LibraryStore()
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(store)
            #if os(macOS)
                .task {
                    while !Task.isCancelled {
                        store.receivePendingCaptures()
                        do { try await Task.sleep(for: .seconds(1)) }
                        catch { break }
                    }
                }
            #endif
        }
    }
}

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
            List {
                Section("Tags") {
                    filterRow("All notes", icon: "tray.full", filter: .all, count: store.library.notes.count)
                    filterRow("Untagged", icon: "tag.slash", filter: .untagged, count: store.library.notes.filter { $0.tags.isEmpty }.count)
                    ForEach(tags, id: \.self) { tag in
                        filterRow(tag, color: store.library.color(for: tag), filter: .tag(tag), count: store.library.notes.filter { TagFilter.tag(tag).includes($0) }.count)
                    }
                }
                Section("Notes · \(filtered.count)") {
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
            }.navigationTitle("ioant-Note").searchable(text: $query)
                .toolbar {
                    ToolbarItemGroup {
                        Button { syncSettings = true } label: { Label("Cloud sync", systemImage: "icloud") }
                        Button { selecting.toggle(); checked.removeAll() } label: { Label(selecting ? "Done" : "Select", systemImage: selecting ? "checkmark" : "checkmark.circle") }
                    }
                }
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 380)
                #endif
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 8) {
                        pasteButton
                        Button { importing = true } label: {
                            Label("Import web capture", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(.regularMaterial)
                }
                .safeAreaInset(edge: .bottom) {
                    if selecting { HStack { Text("\(checked.count) selected"); Spacer(); Button("Merge") { if let id = store.change({ $0.merge(checked) }) ?? nil { selected = id; compactColumn = .detail; selecting = false; checked.removeAll() } }.disabled(checked.count < 2); Button(role: .destructive) { deleting = checked; confirmDelete = true } label: { Image(systemName: "trash") }.disabled(checked.isEmpty) }.padding().background(.regularMaterial) }
                }
        } detail: {
            if let note = current {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(note.title).font(.title2.bold())
                            Spacer()
                            Button { plainPreview.toggle() } label: {
                                Label(plainPreview ? "Rich text" : "Plain text", systemImage: plainPreview ? "doc.richtext" : "text.alignleft")
                            }
                            .buttonStyle(.bordered)
                            .disabled(note.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button { Clipboard.copy(note); copiedID = note.id } label: {
                                Label(copiedID == note.id ? "Copied" : "Copy note", systemImage: copiedID == note.id ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        if !note.tags.isEmpty { TagChipRow(tags: note.tags, color: store.library.color(for:)) }
                        let suggestions = TagSuggestions.forNote(note, existingTags: tags)
                        if !suggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    Text("Suggested tags").font(.caption).foregroundStyle(.secondary)
                                    ForEach(suggestions, id: \.self) { tag in
                                        Button {
                                            _ = store.change { $0.update(note.id, title: note.title, tags: note.tags + [tag]) }
                                        } label: {
                                            Label(tag, systemImage: "plus").font(.caption)
                                        }.buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                        if let source = note.parts.first?.sourceURL { Text(source).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled) }
                    }.padding()
                    Divider()
                    if plainPreview && !note.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ScrollView {
                            Text(note.plainText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(16)
                        }
                    } else {
                        HTMLPreview(html: note.htmlDocument).id(note.id)
                    }
                }.toolbar { ToolbarItemGroup { Button { editing = note } label: { Label("Edit title and tags", systemImage: "tag") }; Button(role: .destructive) { deleting = [note.id]; confirmDelete = true } label: { Label("Delete", systemImage: "trash") } } }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Create a note from clipboard").font(.title2.bold())
                    Text("Copy text, images or formatted web content, then paste to create a new note.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(action: paste) {
                        Label("Paste as new note", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button("Import web capture") { importing = true }
                        .buttonStyle(.bordered)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
            EditNote(note: note, library: store.library) { title, tags, colors in
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
        .confirmationDialog("Delete \(deleting.count) note(s)?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Delete", role: .destructive) { if store.change({ $0.delete(deleting) }) != nil { if let selected, deleting.contains(selected) { self.selected = nil; compactColumn = .sidebar }; checked.subtract(deleting) }; deleting.removeAll() } }
        .alert("ioant-Note", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private func filterRow(_ name: String, icon: String = "tag.fill", color: TagColor? = nil, filter: TagFilter, count: Int) -> some View {
        Button {
            tagFilter = filter
            checked.removeAll()
            if let note = current, !filter.includes(note) { selected = nil }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).foregroundStyle(color?.swiftUIColor ?? Color.secondary)
                Text(LocalizedStringKey(name)).lineLimit(1)
                Spacer()
                Text(count.formatted()).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(tagFilter == filter ? Color.accentColor.opacity(0.15) : Color.clear)
        .accessibilityAddTraits(tagFilter == filter ? [.isSelected] : [])
    }
    private var pasteButton: some View {
        Button(action: paste) {
            Label("Paste as new note", systemImage: "doc.on.clipboard")
                .frame(maxWidth: .infinity)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut("v", modifiers: .command)
        .accessibilityIdentifier("paste-new-note")
        .help("Create a note from clipboard")
    }
    func paste() {
        guard let part = Clipboard.read(), !part.isEmpty else { store.error = "No supported content in the clipboard."; return }
        if let id = store.change({ $0.add(part) }) ?? nil { selected = id; compactColumn = .detail; tagFilter = .all; query = "" }
    }
}

#if os(macOS)
struct HTMLPreview: NSViewRepresentable {
    let html: String
    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
    func makeNSView(context: Context) -> WKWebView { previewWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.render(html, in: view) }
}
#else
struct HTMLPreview: UIViewRepresentable {
    let html: String
    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
    func makeUIView(context: Context) -> WKWebView { previewWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.render(html, in: view) }
}
#endif
