import SwiftUI

struct ClipReaderHeader: View {
    let note: Note
    @Binding var plainPreview: Bool
    @Binding var copiedID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.small) {
            Text(verbatim: note.title)
                .font(.title2.bold())
                .lineLimit(3)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack { date; Spacer(minLength: LayoutMetrics.small); controls }
                VStack(alignment: .leading, spacing: LayoutMetrics.xSmall) { date; controls }
            }
        }
    }
    private var date: some View {
        Text(note.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
    }
    private var controls: some View {
        HStack(spacing: LayoutMetrics.small) {
            Button { plainPreview.toggle() } label: {
                Label(LocalizedStringKey(plainPreview ? "reader.rich" : "reader.plain"), systemImage: plainPreview ? "doc.richtext" : "text.alignleft")
            }
            .buttonStyle(.bordered)
            .disabled(note.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("clip-reader-mode")
            Button { Clipboard.copy(note); copiedID = note.id } label: {
                Label(LocalizedStringKey(copiedID == note.id ? "reader.copied" : "reader.copy"), systemImage: copiedID == note.id ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("clip-copy")
        }
        .controlSize(.small)
    }
}
