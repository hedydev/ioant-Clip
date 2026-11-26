import Foundation

public struct SyncedPreferences: Codable, Equatable, Sendable {
    public let language: String
    public let appearance: String
    public let accent: String

    public init(language: String, appearance: String, accent: String) {
        self.language = language
        self.appearance = appearance
        self.accent = accent
    }

    /// Apply local fields edited after the last common snapshot. Other fields
    /// use the cloud value, including when a device joins for the first time.
    public func merging(remote: Self, lastSynced: Self?) -> Self {
        Self(
            language: lastSynced.map { $0.language != language } == true ? language : remote.language,
            appearance: lastSynced.map { $0.appearance != appearance } == true ? appearance : remote.appearance,
            accent: lastSynced.map { $0.accent != accent } == true ? accent : remote.accent
        )
    }
}
