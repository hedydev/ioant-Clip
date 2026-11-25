import SwiftUI

struct EditClipView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var newColor: TagColor = .gray
    @State private var changes: [String: TagColor] = [:]
    let note: Note
    let library: NoteLibrary
    let save: (String, [String], [String: TagColor]) -> Bool
    init(note: Note, library: NoteLibrary, save: @escaping (String, [String], [String: TagColor]) -> Bool) {
        self.note = note; self.library = library; self.save = save
        _title = State(initialValue: note.title); _tags = State(initialValue: note.tags)
    }
    private var name: String { newTag.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var available: [String] { library.allTags.filter { candidate in !tags.contains { TagColor.key($0) == TagColor.key(candidate) } } }
    private var suggestions: [String] { TagSuggestions.forNote(Note(title: title, tags: tags, parts: note.parts), existingTags: library.allTags) }
    private func color(_ tag: String) -> TagColor { changes[TagColor.key(tag)] ?? library.color(for: tag) }
    private func add(_ tag: String, chosen: TagColor? = nil) {
        let canonical = library.allTags.first { TagColor.key($0) == TagColor.key(tag) } ?? tag
        guard !TagColor.key(canonical).isEmpty, !tags.contains(where: { TagColor.key($0) == TagColor.key(canonical) }) else { return }
        tags.append(canonical)
        if let chosen { changes[TagColor.key(canonical)] = chosen }
        newTag = ""; newColor = .gray
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Title").font(.headline)
                        TextField("Title", text: $title).textFieldStyle(.roundedBorder)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags").font(.headline)
                        if tags.isEmpty { Text("No tags yet").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(tags, id: \.self) { tag in
                            HStack {
                                TagChip(tag: tag, color: color(tag))
                                Spacer()
                                Menu {
                                    ForEach(TagColor.allCases, id: \.self) { item in
                                        Button { changes[TagColor.key(tag)] = item } label: {
                                            Label(item.label, systemImage: color(tag) == item ? "checkmark.circle.fill" : "circle.fill")
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Circle().fill(color(tag).swiftUIColor).frame(width: 14, height: 14)
                                        Text("Color")
                                    }
                                }
                                Button {
                                    tags.removeAll { TagColor.key($0) == TagColor.key(tag) }
                                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Remove tag") + Text(" \(tag)"))
                            }
                        }
                        Text("Tag colors are shared across clips.").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("New tag").font(.headline)
                        HStack {
                            TextField("Tag name", text: $newTag).textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                                .onSubmit { add(name, chosen: library.allTags.contains { TagColor.key($0) == TagColor.key(name) } ? nil : newColor) }
                            Button("Add") { add(name, chosen: library.allTags.contains { TagColor.key($0) == TagColor.key(name) } ? nil : newColor) }.disabled(name.isEmpty)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28, maximum: 36), spacing: 7)], alignment: .leading, spacing: 8) {
                            ForEach(TagColor.allCases, id: \.self) { item in
                                Button { newColor = item } label: {
                                    ZStack {
                                        Circle().fill(item.swiftUIColor).frame(width: 25, height: 25)
                                        if newColor == item { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                                    }.frame(width: 32, height: 32)
                                }.buttonStyle(.plain).accessibilityLabel(Text(item.label))
                                .accessibilityAddTraits(newColor == item ? [.isSelected] : [])
                            }
                        }
                    }
                    if !suggestions.isEmpty {
                        choices("Suggested tags", values: suggestions)
                        Text("Suggestions are local rules. Nothing is added automatically.").font(.caption).foregroundStyle(.secondary)
                    }
                    if !available.isEmpty { choices("Existing tags", values: available) }
                }.padding(20)
            }
            .navigationTitle("Edit clip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !name.isEmpty {
                            add(name, chosen: library.allTags.contains { TagColor.key($0) == TagColor.key(name) } ? nil : newColor)
                        }
                        if save(title, tags, changes.filter { key, _ in tags.contains { TagColor.key($0) == key } }) { dismiss() }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 420, idealHeight: 580)
        #endif
    }
    private func choices(_ heading: LocalizedStringKey, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(values, id: \.self) { tag in
                    Button { add(tag) } label: {
                        HStack(spacing: 4) { Image(systemName: "plus").font(.caption); TagChip(tag: tag, color: color(tag)) }
                    }.buttonStyle(.bordered)
                }
            }
        }
    }
}
