import SwiftUI

/// Static sample of app chrome, never renders or modifies actual saved content.
struct ThemePreview: View {
    @Environment(\.clipTheme) private var theme
    @EnvironmentObject private var language: LanguagePreferences
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.small) {
            Text(verbatim: language.localized("settings.appearance.preview"))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            HStack {
                Label { Text(verbatim: language.localized("library.all")) } icon: { Image(systemName: "tray.full") }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.action)
            }
            .padding(LayoutMetrics.small)
            .background(theme.selectedFilter, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: LayoutMetrics.small) {
                Image(systemName: "doc.on.clipboard").foregroundStyle(theme.action)
                Text(verbatim: language.localized("library.paste")).font(.subheadline)
                Spacer(minLength: 0)
            }
            .padding(LayoutMetrics.small)
        }
        .padding(LayoutMetrics.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
