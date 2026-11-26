import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Compact widths use a native menu; regular widths keep the full sidebar.
struct LibraryFilters: View {
    @Environment(\.clipTheme) private var theme
    let library: NoteLibrary
    let selection: TagFilter
    let compact: Bool
    let select: (TagFilter) -> Void
    private var filters: [TagFilter] { [.all, .untagged] + library.allTags.map(TagFilter.tag) }
    private func title(_ filter: TagFilter) -> Text {
        switch filter {
        case .all: Text("library.all")
        case .untagged: Text("library.untagged")
        case .tag(let name): Text(verbatim: name)
        }
    }
    private func icon(_ filter: TagFilter) -> String {
        switch filter {
        case .all: "tray.full"
        case .untagged: "tag.slash"
        case .tag: "tag.fill"
        }
    }
    private func color(_ filter: TagFilter) -> Color {
        if case .tag(let name) = filter { return library.color(for: name).swiftUIColor }
        return theme.secondaryText
    }
    private func menuIcon(_ filter: TagFilter) -> Image {
        let symbol = selection == filter ? "checkmark" : icon(filter)
        #if os(iOS)
        if let image = UIImage(systemName: symbol) {
            let tint = selection == filter ? theme.action : color(filter)
            return Image(uiImage: image.withTintColor(UIColor(tint), renderingMode: .alwaysOriginal))
        }
        #endif
        return Image(systemName: symbol)
    }

    private func row(_ filter: TagFilter) -> some View {
        HStack(spacing: LayoutMetrics.small) {
            Image(systemName: icon(filter)).foregroundStyle(color(filter))
            title(filter).lineLimit(1)
            Spacer(minLength: LayoutMetrics.xSmall)
            Text(library.notes.filter { filter.includes($0) }.count, format: .number)
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if selection == filter { Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(theme.action) }
        }
        .contentShape(Rectangle())
    }
    var body: some View {
        if compact {
            Menu {
                ForEach(filters, id: \.self) { filter in
                    Button { select(filter) } label: {
                        Label { title(filter) } icon: { menuIcon(filter) }
                    }
                }
            } label: {
                row(selection)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel(Text("library.filter"))
            .accessibilityValue(title(selection))
            .accessibilityIdentifier("clip-filter")
        } else {
            Section("tags.title") {
                ForEach(filters, id: \.self) { filter in
                    Button { select(filter) } label: { row(filter) }
                        .buttonStyle(.plain)
                        .listRowBackground(selection == filter ? theme.selectedFilter : Color.clear)
                        .accessibilityAddTraits(selection == filter ? [.isSelected] : [])
                }
            }
        }
    }
}
