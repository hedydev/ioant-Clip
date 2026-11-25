import SwiftUI

/// Static sample of app chrome, never renders or modifies actual saved content.
struct ThemePreview: View {
    @Environment(\.clipTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.small) {
            Text("settings.appearance.preview")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            HStack {
                Label("library.all", systemImage: "tray.full")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.action)
            }
            .padding(LayoutMetrics.small)
            .background(theme.selectedFilter, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: LayoutMetrics.small) {
                Image(systemName: "doc.on.clipboard").foregroundStyle(theme.action)
                Text("library.paste").font(.subheadline)
                Spacer(minLength: 0)
            }
            .padding(LayoutMetrics.small)
        }
        .padding(LayoutMetrics.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
