import Foundation

enum StorageUsage {
    static func localBytes(libraryURL: URL) throws -> Int64 {
        let directory = libraryURL.deletingLastPathComponent()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey,
                                         .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        var readError: Error?
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys),
            errorHandler: { _, error in readError = error; return false }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        var total: Int64 = 0
        for case let file as URL in files {
            try Task.checkCancellation()
            do {
                let values = try file.resourceValues(forKeys: keys)
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                // SQLite sidecars may disappear while the database is being checkpointed.
                continue
            }
        }
        if let readError { throw readError }
        return total
    }

    private struct CheckpointScope: Decodable {
        let account: SyncAccount
        let zone: String
    }

    static func syncedBytes(libraryURL: URL, account: SyncAccount, zone: String) throws -> Int64? {
        let url = CloudKitReviewConfiguration.checkpointURL(libraryURL: libraryURL)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let scope = try JSONDecoder().decode(CheckpointScope.self, from: data)
        guard scope.account == account, scope.zone == zone else { return nil }

        // The persisted snapshot represents the last confirmed remote history.
        // Its size approximates the revision payloads, including their JSON overhead.
        return Int64(data.count)
    }
}
