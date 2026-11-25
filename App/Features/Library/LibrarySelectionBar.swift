import SwiftUI

struct LibrarySelectionBar: View {
    let count: Int
    let merge: () -> Void
    let delete: () -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { countLabel; Spacer(minLength: LayoutMetrics.small); actions }
            VStack(alignment: .leading, spacing: LayoutMetrics.small) { countLabel; actions }
        }
        .padding(LayoutMetrics.medium)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
    private var countLabel: some View { Text("library.selected \(count)").font(.subheadline) }
    private var actions: some View {
        HStack {
            Button("library.merge", action: merge).buttonStyle(.bordered).disabled(count < 2)
            Button(role: .destructive, action: delete) { Label("common.delete", systemImage: "trash").labelStyle(.iconOnly) }
                .buttonStyle(.bordered).disabled(count == 0)
        }
    }
}
