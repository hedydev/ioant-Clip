import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zhHans = "zh-Hans", zhHant = "zh-Hant", ja, ko
    var id: String { rawValue }
    var autonym: String {
        switch self {
        case .system: ""
        case .en: "English"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .ja: "日本語"
        case .ko: "한국어"
        }
    }
    static func supported(_ locale: Locale) -> Bool {
        let id = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        return ["en","zh","ja","ko"].contains { id == $0 || id.hasPrefix($0+"-") }
    }
}
@MainActor final class LanguagePreferences: ObservableObject {
    private let defaults: UserDefaults
    private static let key = "ioant.clip.preferences.language.v1"
    @Published var selection: AppLanguage {
        didSet { defaults.set(selection.rawValue, forKey: Self.key) }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = AppLanguage(rawValue: defaults.string(forKey: Self.key) ?? "") ?? .system
    }
    func resolvedLocale(system: Locale) -> Locale {
        if selection != .system { return Locale(identifier: selection.rawValue) }
        return AppLanguage.supported(system) ? system : Locale(identifier: "en")
    }
}
struct AppLocaleScope<Content: View>: View {
    @Environment(\.locale) private var systemLocale
    @ObservedObject var preferences: LanguagePreferences
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .environmentObject(preferences)
            .environment(\.locale, preferences.resolvedLocale(system: systemLocale))
    }
}
