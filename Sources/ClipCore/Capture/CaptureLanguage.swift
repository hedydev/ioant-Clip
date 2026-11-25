import Foundation

/// Shared, device-local language preference. Only the allowlisted language
/// identifier is passed to the extensions; no library or account data.
public enum CaptureLanguage {
    public static let codes = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]
    public static func canonical(_ identifier: String) -> String? {
        let id = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let parts = id.split(separator: "-")
        guard let language = parts.first else { return nil }
        switch language {
        case "zh":
            if parts.contains("hans") { return "zh-Hans" }
            if parts.contains("hant") || parts.contains("tw") || parts.contains("hk") || parts.contains("mo") { return "zh-Hant" }
            return "zh-Hans"
        case "en", "ja", "ko": return String(language)
        default: return nil
        }
    }
    public static func resolve(selection: String, preferred: [String]) -> String {
        if codes.contains(selection) { return selection }
        return preferred.compactMap(canonical).first ?? "en"
    }
    public static var groupFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ioant.clip")?
            .appendingPathComponent("interface-language.json")
    }
    public static func read(from url: URL?) -> String? {
        guard let url, let info = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              info.isRegularFile == true, info.isSymbolicLink != true,
              let size = info.fileSize, size <= 256,
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Preference.self, from: data),
              value.version == 1, codes.contains(value.language) else { return nil }
        return value.language
    }
    public static func write(_ language: String, to url: URL) throws {
        guard codes.contains(language) else { return }
        if read(from: url) == language { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Preference(version: 1, language: language))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func localized(_ key: String, language: String, bundle: Bundle = .main) -> String {
        let code = codes.contains(language) ? language : "en"
        if let path = bundle.path(forResource: code, ofType: "lproj"), let localized = Bundle(path: path) {
            return localized.localizedString(forKey: key, value: nil, table: nil)
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
    private struct Preference: Codable {
        let version: Int
        let language: String
    }
}
