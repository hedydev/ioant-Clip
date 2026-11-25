import SwiftUI

struct TagChip: View {
    let tag: String
    let color: TagColor
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color.swiftUIColor).frame(width: 7, height: 7)
            Text(tag).lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, LayoutMetrics.chipHorizontal).padding(.vertical, LayoutMetrics.xSmall)
        .background(color.swiftUIColor.opacity(0.15), in: Capsule())
    }
}
struct TagChipRow: View {
    let tags: [String]
    let color: (String) -> TagColor
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LayoutMetrics.chipSpacing) { ForEach(tags, id: \.self) { TagChip(tag: $0, color: color($0)) } }
        }
    }
}
