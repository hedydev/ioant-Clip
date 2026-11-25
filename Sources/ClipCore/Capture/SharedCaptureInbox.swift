import Foundation

/// Extensions enqueue only validated capture envelopes, never open notes.json.
/// The daily main app is the single writer and uses CaptureInbox.drain.
public enum SharedCaptureInbox {
    public static let group = "group.com.ioant.clip"
    public static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("CaptureInbox", isDirectory: true)
    }
    public static func enqueue(_ data: Data, directory: URL) throws -> UUID {
        _ = try WebCapture.decode(data)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attrs = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard attrs.isDirectory == true, attrs.isSymbolicLink != true else { throw CocoaError(.fileWriteInvalidFileName) }
        let id = UUID()
        let temporary = directory.appendingPathComponent(".incoming-" + id.uuidString)
        let target = directory.appendingPathComponent(id.uuidString + ".json")
        defer { try? fm.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try fm.moveItem(at: temporary, to: target)
        return id
    }
    public static func enqueue(_ data: Data) throws -> UUID {
        guard let directory else { throw CocoaError(.fileWriteNoPermission) }
        return try enqueue(data, directory: directory)
    }
}
