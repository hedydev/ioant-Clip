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
    func resolvedLocale(system: Locale, preferredLanguages: [String]? = nil) -> Locale {
        Locale(identifier: CaptureLanguage.resolve(selection: selection.rawValue, preferred: preferredLanguages ?? [system.identifier]))
    }
    /// Resolve app-owned strings explicitly for native controls that may
    /// snapshot the system locale (sheets, menus, pickers and toolbars).
    func localized(_ key: String, bundle: Bundle = .main) -> String {
        CaptureLanguage.localized(key, language: CaptureLanguage.resolve(selection: selection.rawValue, preferred: Locale.preferredLanguages), bundle: bundle)
    }
    func publishExtensionLanguage(_ language: String) {
        #if CLIP_CAPTURE_EXTENSIONS
        if let url = CaptureLanguage.groupFile { try? CaptureLanguage.write(language, to: url) }
        #if os(macOS)
        let host = URL.applicationSupportDirectory.appending(path: "ioant-Clip/NativeMessaging/interface-language.json")
        try? CaptureLanguage.write(language, to: host)
        #endif
        #endif
    }
}
struct AppLocaleScope<Content: View>: View {
    @Environment(\.locale) private var systemLocale
    @ObservedObject var preferences: LanguagePreferences
    @ViewBuilder let content: () -> Content
    var body: some View {
        let locale = preferences.resolvedLocale(system: systemLocale, preferredLanguages: Locale.preferredLanguages)
        let language = CaptureLanguage.canonical(locale.identifier) ?? "en"
        content()
            .environmentObject(preferences)
            .environment(\.locale, locale)
            .onChange(of: language, initial: true) { _, value in preferences.publishExtensionLanguage(value) }
    }
}
