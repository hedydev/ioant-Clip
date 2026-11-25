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
    init() {
        do { library = try NoteLibrary.load(from: url); ready = true }
        catch { self.error = "Cannot open library. Existing data was not changed: \(error.localizedDescription)" }
    }
    @discardableResult func change<T>(_ mutation: (inout NoteLibrary) -> T) -> T? {
        guard ready else { error = "Library is unavailable."; return nil }
        var next = library; let result = mutation(&next)
        do { try next.save(to: url); library = next; return result }
        catch { self.error = error.localizedDescription; return nil }
    }
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
    static func richHTML(_ data: Data) -> String? {
        guard let string = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil), let html = try? string.data(from: NSRange(location: 0, length: string.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) else { return nil }
        return String(data: html, encoding: .utf8)
    }
}

@main struct NoteApp: App {
    @StateObject private var store = LibraryStore()
    var body: some Scene { WindowGroup { LibraryView().environmentObject(store) } }
}

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var selected: UUID?
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var checked = Set<UUID>()
    @State private var selecting = false
    @State private var query = ""
    @State private var importing = false
    @State private var editing: Note?
    @State private var deleting = Set<UUID>()
    @State private var confirmDelete = false
    @State private var tagFilter: String?
    var current: Note? { store.library.notes.first { $0.id == selected } }
    var tags: [String] { Note.normalizedTags(store.library.notes.flatMap(\.tags)).sorted() }
    var filtered: [Note] { store.library.notes.filter { $0.matches(query) && (tagFilter == nil || $0.tags.contains { $0.caseInsensitiveCompare(tagFilter ?? "") == .orderedSame }) } }
    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List {
                if !tags.isEmpty {
                    Section("Tags") {
                        Picker("Filter", selection: $tagFilter) {
                            Text("All notes").tag(nil as String?)
                            ForEach(tags, id: \.self) { Text($0).tag(Optional($0)) }
                        }
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
                                    if !note.tags.isEmpty { Text(note.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.tint).lineLimit(1) }
                                }
                                Spacer()
                            }.padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain).listRowBackground(selected == note.id ? Color.accentColor.opacity(0.12) : Color.clear)
                    }
                }
            }.navigationTitle("ioant-Note").searchable(text: $query)
                .toolbar {
                    ToolbarItemGroup {
                        Button { paste() } label: { Label("New from clipboard", systemImage: "doc.on.clipboard") }.keyboardShortcut("v", modifiers: .command)
                        Button { importing = true } label: { Label("Import web capture", systemImage: "square.and.arrow.down") }
                        Button { selecting.toggle(); checked.removeAll() } label: { Label(selecting ? "Done" : "Select", systemImage: selecting ? "checkmark" : "checkmark.circle") }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if selecting { HStack { Text("\(checked.count) selected"); Spacer(); Button("Merge") { if let id = store.change({ $0.merge(checked) }) ?? nil { selected = id; compactColumn = .detail; selecting = false; checked.removeAll() } }.disabled(checked.count < 2); Button(role: .destructive) { deleting = checked; confirmDelete = true } label: { Image(systemName: "trash") }.disabled(checked.isEmpty) }.padding().background(.regularMaterial) }
                }
        } detail: {
            if let note = current {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title).font(.title2.bold())
                        if !note.tags.isEmpty { Text(note.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        if let source = note.parts.first?.sourceURL { Text(source).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled) }
                    }.padding()
                    Divider()
                    HTMLPreview(html: note.htmlDocument).id(note.id)
                }.toolbar { ToolbarItemGroup { Button { editing = note } label: { Label("Edit title and tags", systemImage: "tag") }; Button(role: .destructive) { deleting = [note.id]; confirmDelete = true } label: { Label("Delete", systemImage: "trash") } } }
            } else { ContentUnavailableView("No note selected", systemImage: "doc.richtext", description: Text("Paste content or import a browser capture.")) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): if let id = store.importFile(url) { selected = id; compactColumn = .detail; tagFilter = nil; query = "" }; case .failure(let error): store.error = error.localizedDescription }
        }
        .sheet(item: $editing) { note in EditNote(note: note) { title, tags in _ = store.change { $0.update(note.id, title: title, tags: tags) } } }
        .confirmationDialog("Delete \(deleting.count) note(s)?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Delete", role: .destructive) { if store.change({ $0.delete(deleting) }) != nil { if let selected, deleting.contains(selected) { self.selected = nil; compactColumn = .sidebar }; checked.subtract(deleting) }; deleting.removeAll() } }
        .alert("ioant-Note", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    func paste() {
        guard let part = Clipboard.read(), !part.isEmpty else { store.error = "No supported content in the clipboard."; return }
        if let id = store.change({ $0.add(part) }) ?? nil { selected = id; compactColumn = .detail; tagFilter = nil; query = "" }
    }
}

struct EditNote: View {
    @Environment(\.dismiss) var dismiss
    @State var title: String
    @State var tags: String
    let save: (String, [String]) -> Void
    init(note: Note, save: @escaping (String, [String]) -> Void) { _title = State(initialValue: note.title); _tags = State(initialValue: note.tags.joined(separator: ", ")); self.save = save }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Tags (comma separated)", text: $tags)
            }
            .padding()
            .navigationTitle("Edit note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(title, tags.components(separatedBy: CharacterSet(charactersIn: ",，")))
                        dismiss()
                    }
                }
            }
        }
    }
}

final class PreviewCoordinator: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = action.request.url?.scheme ?? ""
        decisionHandler(["about", "data"].contains(scheme) && action.navigationType != .linkActivated ? .allow : .cancel)
    }
}
func previewWebView(_ coordinator: PreviewCoordinator) -> WKWebView {
    let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); config.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = coordinator; return view
}
#if os(macOS)
struct HTMLPreview: NSViewRepresentable {
    let html: String
    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
    func makeNSView(context: Context) -> WKWebView { previewWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { view.loadHTMLString(html, baseURL: nil) }
}
#else
struct HTMLPreview: UIViewRepresentable {
    let html: String
    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
    func makeUIView(context: Context) -> WKWebView { previewWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { view.loadHTMLString(html, baseURL: nil) }
}
#endif
