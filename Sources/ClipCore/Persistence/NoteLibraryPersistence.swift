import Foundation

extension NoteLibrary {
    public static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let library = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard Set(library.notes.map(\.id)).count == library.notes.count else { throw SyncJournal.JournalError.conflictingIdentity }
        if let enrollment = library.syncEnrollment {
            guard library.syncJournal != nil, !enrollment.account.provider.isEmpty, !enrollment.account.namespace.isEmpty, !enrollment.account.accountID.isEmpty else { throw SyncSessionError.persistenceFailed }
        }
        if let journal = library.syncJournal {
            try journal.validate()
        }
        return library
    }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
