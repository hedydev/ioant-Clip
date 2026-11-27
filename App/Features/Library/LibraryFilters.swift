import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LibraryFilters: View {
    @Environment(\.clipTheme) private var theme
    let store: LibraryStore
    let selection: TagFilter
    let visibleTags: [String]
    let compact: Bool
    let select: (TagFilter) -> Void
    let edit: () -> Void

    private var filters: [TagFilter] { [.all, .untagged] + store.allTags.map(TagFilter.tag) }
    private var shortcuts: [TagFilter] { visibleTags.map(TagFilter.tag) }
    private var desktopRows: [TagFilter] { [.all, .untagged] + shortcuts }

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: LayoutMetrics.small) {
                HStack(spacing: LayoutMetrics.medium) {
                    filterMenu {
                        HStack(spacing: LayoutMetrics.small) {
                            row(selection)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                    }
                    editButton
                }
                if !shortcuts.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: LayoutMetrics.small) {
                            ForEach(shortcuts, id: \.self) { filter in
                                Button { select(filter) } label: {
                                    Label { title(filter).lineLimit(1) } icon: {
                                        Image(systemName: icon(filter)).foregroundStyle(color(filter))
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, LayoutMetrics.small)
                                    .padding(.vertical, LayoutMetrics.xSmall)
                                    .frame(maxWidth: 160)
                                    .background(isSelected(filter) ? theme.selectedFilter : Color.secondary.opacity(0.10), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isSelected(filter) ? [.isSelected] : [])
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, LayoutMetrics.medium)
            .padding(.vertical, LayoutMetrics.small)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: LayoutMetrics.small) {
                    Text("tags.title").accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if store.allTags.count > visibleTags.count {
                        filterMenu {
                            Label("library.filter", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                    editButton
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, LayoutMetrics.medium)
                .padding(.vertical, LayoutMetrics.xSmall)
                ForEach(desktopRows, id: \.self) { filter in
                    Button { select(filter) } label: {
                        row(filter)
                            .padding(.horizontal, LayoutMetrics.medium)
                            .padding(.vertical, LayoutMetrics.xSmall)
                            .background(isSelected(filter) ? theme.selectedFilter : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected(filter) ? [.isSelected] : [])
                }
            }
        }
    }

    private var editButton: some View {
        Button(action: edit) {
            Label("tags.display", systemImage: "slider.horizontal.3").labelStyle(.iconOnly)
                .foregroundStyle(theme.action)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("tags.display"))
        .accessibilityIdentifier("clip-edit-visible-tags")
    }

    private func filterMenu<LabelContent: View>(@ViewBuilder label: () -> LabelContent) -> some View {
        Menu {
            ForEach(filters, id: \.self) { filter in
                Button { select(filter) } label: {
                    Label { title(filter) } icon: { menuIcon(filter) }
                }
            }
        } label: {
            label()
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("library.filter"))
        .accessibilityValue(title(selection))
        .accessibilityIdentifier("clip-filter")
    }

    private func isSelected(_ filter: TagFilter) -> Bool {
        if case .tag(let selected) = selection, case .tag(let name) = filter {
            return TagColor.key(selected) == TagColor.key(name)
        }
        return selection == filter
    }

    private func count(_ filter: TagFilter) -> Int {
        switch filter {
        case .all: store.totalCount
        case .untagged: store.untaggedCount
        case .tag(let name): store.tagCounts[name] ?? 0
        }
    }

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
        if case .tag(let name) = filter { return store.color(for: name).swiftUIColor }
        return theme.secondaryText
    }

    private func menuIcon(_ filter: TagFilter) -> Image {
        let symbol = isSelected(filter) ? "checkmark" : icon(filter)
        #if os(iOS)
        if let image = UIImage(systemName: symbol) {
            let tint = isSelected(filter) ? theme.action : color(filter)
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
            Text(count(filter), format: .number)
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if isSelected(filter) {
                Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(theme.action)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .contentShape(Rectangle())
    }
}
