import SwiftUI

struct ClipDetailView: View {
    @EnvironmentObject var store: LibraryStore
    let current: Note?
    let tags: [String]
    @Binding var plainPreview: Bool
    @Binding var copiedID: UUID?
    @Binding var editing: Note?
    @Binding var deleting: Set<UUID>
    @Binding var confirmDelete: Bool
    @Binding var importing: Bool
    let paste: () -> Void
    var body: some View {
            if let note = current {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(note.title).font(.title2.bold())
                            Spacer()
                            Button { plainPreview.toggle() } label: {
                                Label(LocalizedStringKey(plainPreview ? "reader.rich" : "reader.plain"), systemImage: plainPreview ? "doc.richtext" : "text.alignleft")
                            }
                            .buttonStyle(.bordered)
                            .disabled(note.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button { Clipboard.copy(note); copiedID = note.id } label: {
                                Label(LocalizedStringKey(copiedID == note.id ? "reader.copied" : "reader.copy"), systemImage: copiedID == note.id ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
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
                        if let source = note.parts.first?.sourceURL { Text(source).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled) }
                    }.padding()
                    Divider()
                    if plainPreview && !note.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ScrollView {
                            Text(note.plainText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(LayoutMetrics.large)
                        }
                    } else {
                        HTMLPreview(html: note.htmlDocument).id(note.id)
                    }
                }.toolbar { ToolbarItemGroup { Button { editing = note } label: { Label("reader.edit", systemImage: "tag") }; Button(role: .destructive) { deleting = [note.id]; confirmDelete = true } label: { Label("common.delete", systemImage: "trash") } } }
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
