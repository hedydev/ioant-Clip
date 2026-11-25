import SwiftUI

struct ClipDetailView: View {
    @EnvironmentObject var store: LibraryStore
    let current: Note?
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
                        ClipReaderHeader(note: note, plainPreview: $plainPreview, copiedID: $copiedID)
                        if !note.tags.isEmpty { TagChipRow(tags: note.tags, color: store.library.color(for:)) }
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
                    if showingMedia {
                        ClipMediaView(items: note.media, parentSize: sheetParentSize).id(note.id)
                    } else if plainPreview && !note.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ScrollView {
                            Text(note.plainText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(LayoutMetrics.large)
                        }
                    } else {
                        HTMLPreview(html: note.htmlDocument).id(note.id)
                    }
                }.toolbar {
                    ToolbarItemGroup {
                        Button { editing = note } label: { Label("reader.edit", systemImage: "tag") }
                        Button(role: .destructive) { deleting = [note.id]; confirmDelete = true } label: { Label("common.delete", systemImage: "trash") }
                    }
                }
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
