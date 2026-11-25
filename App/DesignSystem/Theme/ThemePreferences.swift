import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: LocalizedStringKey { LocalizedStringKey(localizationKey) }
    var localizationKey: String {
        switch self {
        case .system: "settings.appearance.system"
        case .light: "settings.appearance.light"
        case .dark: "settings.appearance.dark"
        }
    }
    var preferredScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

/// Accent identity is deliberately separate from a persisted TagColor.
enum AppAccent: String, CaseIterable, Identifiable {
    case blue, purple, teal, green, orange, pink, graphite
    var id: String { rawValue }
    var label: LocalizedStringKey { LocalizedStringKey(localizationKey) }
    var localizationKey: String {
        switch self {
        case .blue: "color.blue"
        case .purple: "color.purple"
        case .teal: "color.teal"
        case .green: "color.green"
        case .orange: "color.orange"
        case .pink: "color.pink"
        case .graphite: "color.graphite"
        }
    }
    /// Native adaptive colors keep system appearance and accessibility behavior.
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .graphite: .gray
        }
    }
}

@MainActor final class ThemePreferences: ObservableObject {
    private let defaults: UserDefaults
    static let appearanceKey = "ioant.clip.preferences.appearance.v1"
    static let accentKey = "ioant.clip.preferences.accent.v1"

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    @Published var accent: AppAccent {
        didSet { defaults.set(accent.rawValue, forKey: Self.accentKey) }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppAppearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
        accent = AppAccent(rawValue: defaults.string(forKey: Self.accentKey) ?? "") ?? .blue
    }
    func reset() {
        appearance = .system
        accent = .blue
    }
}
