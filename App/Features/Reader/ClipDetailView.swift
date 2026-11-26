import SwiftUI

struct ClipDetailView: View {
    @EnvironmentObject var store: LibraryStore
    let current: Note?
    let loadingNote: Bool
    let sheetParentSize: CGSize
    let tags: [String]
    @Binding var plainPreview: Bool
    @Binding var copiedID: UUID?
    @Binding var editing: Note?
    @Binding var deleting: Set<UUID>
    @Binding var confirmDelete: Bool
    @Binding var importing: Bool
    let paste: () -> Void
    @State private var showingMedia = false
    var body: some View {
            if let note = current {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        ClipReaderHeader(note: note, plainPreview: Binding(
                            get: { plainPreview },
                            set: { plainPreview = $0; showingMedia = false }
                        ), copiedID: $copiedID)
                        if !note.tags.isEmpty { TagChipRow(tags: note.tags, color: store.color(for:)) }
                        let suggestions = TagSuggestions.forNote(note, existingTags: tags)
                        if !suggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    Text("tags.suggested").font(.caption).foregroundStyle(.secondary)
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
                        if let source = note.parts.first?.sourceURL { Text(verbatim: source).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled) }
                    }.padding(LayoutMetrics.large)
                    Picker("reader.media", selection: $showingMedia) {
                        Text("reader.original").tag(false)
                        Text("reader.media").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, LayoutMetrics.large)
                    .padding(.bottom, 8)
                    Divider()
                    ClipReaderContent(note: note, mode: showingMedia ? .media : (plainPreview ? .plain : .original),
                                      sheetParentSize: sheetParentSize)
                        .id(note.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.toolbar {
                    ToolbarItemGroup {
                        Button { editing = note } label: { Label("reader.edit", systemImage: "tag") }
                        Button(role: .destructive) { deleting = [note.id]; confirmDelete = true } label: { Label("common.delete", systemImage: "trash") }
                    }
                }
            } else if loadingNote {
                ReaderLoadingView()
            } else {
                VStack(spacing: LayoutMetrics.large) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("library.empty.title").font(.title2.bold())
                    Text("library.empty.description")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(action: paste) {
                        Label("library.paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button("library.import") { importing = true }
                        .buttonStyle(.bordered)
                }
                .padding(LayoutMetrics.xLarge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }
}

private struct ClipReaderContent: View {
    enum Mode: Hashable, Sendable { case original, plain, media }

    private enum Prepared: Sendable {
        case html(String)
        case plain(String)
        case media([NoteMedia])
    }

    private struct Request: Equatable {
        let parts: [NotePart]
        let mode: Mode
    }

    let note: Note
    let mode: Mode
    let sheetParentSize: CGSize
    @State private var preparedParts: [NotePart]?
    @State private var cache: [Mode: Prepared] = [:]

    private var request: Request { Request(parts: note.parts, mode: mode) }

    var body: some View {
        Group {
            if preparedParts == note.parts, let content = cache[mode] {
                switch content {
                case .html(let html):
                    ReaderHTMLPreview(html: html)
                case .plain(let text):
                    ScrollView {
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(LayoutMetrics.large)
                    }
                case .media(let items):
                    ClipMediaView(items: items, parentSize: sheetParentSize)
                }
            } else {
                ReaderLoadingView()
            }
        }
        .task(id: request) { [request, note] in
            if preparedParts != request.parts {
                preparedParts = request.parts
                cache.removeAll()
            }
            guard !Task.isCancelled, cache[request.mode] == nil else { return }
            let mode = request.mode
            let content = await Task.detached(priority: .userInitiated) {
                switch mode {
                case .original: Prepared.html(note.htmlDocument)
                case .media: Prepared.media(note.media)
                case .plain:
                    Self.preparePlainText(for: note)
                }
            }.value
            guard !Task.isCancelled, preparedParts == request.parts else { return }
            cache[mode] = content
        }
    }
    private nonisolated static func preparePlainText(for note: Note) -> Prepared {
        let text = note.plainText
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .html(note.htmlDocument) : .plain(text)
    }
}

struct ReaderLoadingView: View {
    var compact = false
    @State private var visible = false

    var body: some View {
        Group {
            if compact {
                ProgressView().controlSize(.small)
            } else {
                ProgressView("reader.loading")
            }
        }
        .opacity(visible ? 1 : 0)
        .accessibilityHidden(!visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { visible = true }
        }
    }
}
