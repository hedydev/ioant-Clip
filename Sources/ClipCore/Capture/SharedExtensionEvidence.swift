import Foundation

/// Device-local evidence only. No note content, URL, identifiers or account data.
public struct SharedExtensionEvidence: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case safari, share }
    public enum Activity: String, Codable, Sendable { case ping, queued }
    public let version: Int
    public let source: Source
    public let activity: Activity
    public let unixSeconds: Double

    public static var directory: URL? {
        SharedCaptureInbox.directory?.deletingLastPathComponent()
    }
    private static func file(_ source: Source, _ directory: URL) -> URL {
        directory.appendingPathComponent("extension-\(source.rawValue)-contact.json")
    }
    public static func read(_ source: Source, directory: URL? = directory, now: Date = Date()) -> Self? {
        guard let directory else { return nil }
        let url = file(source, directory)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 512,
              let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode(Self.self, from: data),
              result.version == 1, result.source == source,
              result.unixSeconds > 0, result.unixSeconds <= now.timeIntervalSince1970 + 60,
              source != .share || result.activity == .queued else { return nil }
        return result
    }
    public static func record(_ source: Source, activity: Activity, directory: URL? = directory, now: Date = Date()) throws {
        guard let directory else { throw CocoaError(.fileWriteNoPermission) }
        guard source != .share || activity == .queued else { throw CocoaError(.fileWriteUnknown) }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let attrs = try directory.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey])
        guard attrs.isDirectory == true, attrs.isSymbolicLink != true else { throw CocoaError(.fileWriteInvalidFileName) }
        let data = try JSONEncoder().encode(Self(version: 1, source: source, activity: activity, unixSeconds: now.timeIntervalSince1970))
        let url = file(source, directory)
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
