import SwiftUI

/// Semantic roles, not view-specific hard-coded brand colors.
/// Use native primary/secondary/material roles for neutral surfaces.
struct ClipTheme {
    let accent: AppAccent
    var action: Color { accent.color }
    var primaryText: Color { .primary }
    var secondaryText: Color { .secondary }
    var selectedRow: Color { action.opacity(0.12) }
    var selectedFilter: Color { action.opacity(0.15) }
    var success: Color { .green }
    var warning: Color { .orange }
    var destructive: Color { .red }
}

private struct ClipThemeKey: EnvironmentKey {
    static let defaultValue = ClipTheme(accent: .blue)
}
extension EnvironmentValues {
    var clipTheme: ClipTheme {
        get { self[ClipThemeKey.self] }
        set { self[ClipThemeKey.self] = newValue }
    }
}

struct AppThemeScope<Content: View>: View {
    @ObservedObject var preferences: ThemePreferences
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .environmentObject(preferences)
            .environment(\.clipTheme, ClipTheme(accent: preferences.accent))
            .tint(preferences.accent.color)
            .preferredColorScheme(preferences.appearance.preferredScheme)
    }
}
