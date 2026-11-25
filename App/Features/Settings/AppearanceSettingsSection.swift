import SwiftUI

struct AppearanceSettingsSection: View {
    @EnvironmentObject private var theme: ThemePreferences
    var body: some View {
        Section {
            Picker("settings.appearance.mode", selection: $theme.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Label(appearance.label, systemImage: appearance.symbol).tag(appearance)
                }
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
            Text("settings.appearance.description")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("settings.appearance.reset") { theme.reset() }
        } header: {
            Text("settings.appearance")
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
