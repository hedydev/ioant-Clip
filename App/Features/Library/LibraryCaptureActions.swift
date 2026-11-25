import SwiftUI

struct LibraryCaptureActions: View {
    let compact: Bool
    let paste: () -> Void
    let importFile: () -> Void
    var body: some View {
        if compact {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: LayoutMetrics.small) { pasteButton; importButton }
                VStack(spacing: LayoutMetrics.small) { pasteButton; importButton }
            }
        } else {
            VStack(spacing: LayoutMetrics.small) { pasteButton; importButton }
        }
    }
    private var pasteButton: some View {
        Button(action: paste) {
            Label("library.paste", systemImage: "doc.on.clipboard")
                .frame(maxWidth: .infinity)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut("v", modifiers: .command)
        .accessibilityIdentifier("paste-new-note")
        .help("library.empty.title")
    }
    private var importButton: some View {
        Button(action: importFile) {
            Label("library.import", systemImage: "square.and.arrow.down")
                .modifier(CaptureImportLabelStyle(compact: compact))
                .frame(maxWidth: compact ? nil : .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help("library.import")
        .accessibilityIdentifier("clip-import")
    }
}

private struct CaptureImportLabelStyle: ViewModifier {
    let compact: Bool
    func body(content: Content) -> some View {
        if compact { content.labelStyle(.iconOnly) }
        else { content.labelStyle(.titleAndIcon) }
    }
}
