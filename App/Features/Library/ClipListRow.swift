import SwiftUI

struct ClipListRow: View {
    let note: Note
    let selecting: Bool
    let checked: Bool
    let color: (String) -> TagColor
    private var source: String? {
        guard let raw = note.parts.first?.sourceURL else { return nil }
        return URL(string: raw)?.host ?? raw
    }
    var body: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.small) {
            if selecting {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: LayoutMetrics.chipSpacing) {
                Text(verbatim: note.title).font(.headline).lineLimit(2)
                let summary = note.parts.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !summary.isEmpty { Text(verbatim: summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: LayoutMetrics.small) { metadata }
                    VStack(alignment: .leading, spacing: LayoutMetrics.xSmall) { metadata }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if !note.tags.isEmpty { TagChipRow(tags: note.tags, color: color) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, LayoutMetrics.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var metadata: some View {
        Text(note.createdAt, style: .date)
        if let source { Text(verbatim: source).lineLimit(1).truncationMode(.middle) }
    }
}
