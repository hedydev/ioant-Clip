import SwiftUI

struct AppearanceSettingsSection: View {
    @EnvironmentObject private var theme: ThemePreferences
    @EnvironmentObject private var language: LanguagePreferences
    var body: some View {
        ModalSection(title: "settings.appearance") {
            VStack(alignment: .leading, spacing: LayoutMetrics.small) {
                Text(verbatim: language.localized("settings.appearance.mode")).font(.subheadline.weight(.medium))
                Picker(selection: $theme.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Label { Text(verbatim: language.localized(appearance.localizationKey)) } icon: { Image(systemName: appearance.symbol) }.tag(appearance)
                }
            } label: { Text(verbatim: language.localized("settings.appearance.mode")) }
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: language.localized("settings.appearance.mode")))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: LayoutMetrics.medium) {
                Text(verbatim: language.localized("settings.appearance.accent")).font(.subheadline.weight(.medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: LayoutMetrics.small)], alignment: .leading, spacing: LayoutMetrics.medium) {
                    ForEach(AppAccent.allCases) { accent in
                        Button { theme.accent = accent } label: {
                            AccentSwatch(accent: accent, selected: theme.accent == accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: language.localized(accent.localizationKey)))
                        .accessibilityAddTraits(theme.accent == accent ? [.isSelected] : [])
                    }
                }
                ThemePreview()
            }
            .padding(.vertical, LayoutMetrics.small)
            ModalDescription(key: "settings.appearance.description")
            Button { theme.reset() } label: { Text(verbatim: language.localized("settings.appearance.reset")) }
        }
    }
}

private struct AccentSwatch: View {
    @EnvironmentObject private var language: LanguagePreferences
    let accent: AppAccent
    let selected: Bool
    var body: some View {
        VStack(spacing: LayoutMetrics.xSmall) {
            ZStack {
                Circle().fill(accent.color).frame(width: 30, height: 30)
                Circle().strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 2).frame(width: 40, height: 40)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.primary, Color.white)
                        .font(.system(size: 14, weight: .semibold))
                        .offset(x: 14, y: 14)
                }
            }
            .frame(width: 44, height: 44)
            Text(verbatim: language.localized(accent.localizationKey))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
