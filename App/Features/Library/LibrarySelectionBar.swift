import SwiftUI

struct LibrarySelectionBar: View {
    let count: Int
    let merge: () -> Void
    let delete: () -> Void
    let done: () -> Void

    var body: some View {
        HStack(spacing: LayoutMetrics.medium) {
            Button(action: merge) {
                Label("library.merge", systemImage: "arrow.triangle.merge")
            }
            .disabled(count < 2)
            .help(Text("library.merge"))
            .accessibilityIdentifier("clip-merge")
            Button(role: .destructive, action: delete) {
                Label("common.delete", systemImage: "trash")
            }
            .disabled(count == 0)
            .help(Text("common.delete"))
            Button(action: done) {
                Label("common.done", systemImage: "checkmark")
            }
            .help(Text("common.done"))
            .accessibilityIdentifier("clip-select")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}
