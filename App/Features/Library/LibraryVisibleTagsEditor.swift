import SwiftUI

struct LibraryVisibleTagsEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var selected: Set<String>
    @State private var query = ""

    private var available: [String] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.allTags.filter { search.isEmpty || $0.localizedStandardContains(search) }
    }

    var body: some View {
        ModalScrollPage {
            Text("tags.display.limit \(VisibleLibraryTags.limit)").foregroundStyle(.secondary)
            TextField("tags.display.search", text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            if available.isEmpty {
                Text(LocalizedStringKey(store.allTags.isEmpty ? "tags.empty" : "tags.display.noResults"))
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: LayoutMetrics.medium) {
                    ForEach(available, id: \.self) { tag in
                        let key = TagColor.key(tag)
                        Toggle(isOn: Binding(
                            get: { selected.contains(key) },
                            set: { show in
                                if !show { selected.remove(key) }
                                else if selected.count < VisibleLibraryTags.limit { selected.insert(key) }
                            }
                        )) {
                            Label {
                                Text(verbatim: tag)
                            } icon: {
                                Image(systemName: "tag.fill").foregroundStyle(store.color(for: tag).swiftUIColor)
                            }
                        }
                        .disabled(!selected.contains(key) && selected.count >= VisibleLibraryTags.limit)
                    }
                }
            }
        }
    }
}
