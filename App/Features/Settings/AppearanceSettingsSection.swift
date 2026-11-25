import SwiftUI

struct AppearanceSettingsSection: View {
    @EnvironmentObject private var theme: ThemePreferences
    var body: some View {
        ModalSection(title: "settings.appearance") {
            VStack(alignment: .leading, spacing: LayoutMetrics.small) {
                Text("settings.appearance.mode").font(.subheadline.weight(.medium))
                Picker("settings.appearance.mode", selection: $theme.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Label(appearance.label, systemImage: appearance.symbol).tag(appearance)
                }
            }
                .labelsHidden()
                .accessibilityLabel(Text("settings.appearance.mode"))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: LayoutMetrics.medium) {
                Text("settings.appearance.accent").font(.subheadline.weight(.medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: LayoutMetrics.small)], alignment: .leading, spacing: LayoutMetrics.medium) {
                    ForEach(AppAccent.allCases) { accent in
                        Button { theme.accent = accent } label: {
                            AccentSwatch(accent: accent, selected: theme.accent == accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(accent.label))
                        .accessibilityAddTraits(theme.accent == accent ? [.isSelected] : [])
                    }
                }
                ThemePreview()
            }
            .padding(.vertical, LayoutMetrics.small)
            ModalDescription(key: "settings.appearance.description")
            Button("settings.appearance.reset") { theme.reset() }
        }
    }
}

private struct AccentSwatch: View {
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
            Text(accent.label)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
