import Foundation

/// Durable handoff from the local browser host. Only UUID-named regular files
/// are consumed, and files remain until the library has been saved.
public enum CaptureInbox {
    public struct Result: Equatable {
        public var imported: [UUID] = []
        public var failures: [String] = []
    }
    public static func drain(directory: URL, libraryURL: URL, library: inout NoteLibrary) throws -> Result {
        try drain(directory: directory) { id, read in
            if library.notes.contains(where: { $0.id == id }) { return false }
            let capture = try read()
            var next = library
            guard next.add(capture.part, title: capture.title, id: id) != nil else { throw WebCapture.ImportError.empty }
            try next.recordLocalChanges(from: library)
            try next.save(to: libraryURL)
            library = next
            return true
        }
    }

    public static func drain(directory: URL, importCapture: (UUID, () throws -> WebCapture) throws -> Bool) throws -> Result {
        let fm = FileManager.default
        // fileExists conflates a missing inbox with permission denial. Only
        // an actual not-found error is treated as an empty queue.
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey]
        let files: [URL]
        do {
            let attributes = try directory.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey])
            guard attributes.isDirectory == true, attributes.isSymbolicLink != true else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return Result()
        }
        let pending = files
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
            }
        var result = Result()
        for file in pending.prefix(20) {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            do {
                let attrs = try file.resourceValues(forKeys: keys)
                guard attrs.isRegularFile == true, attrs.isSymbolicLink != true else { continue }
                if try importCapture(id, {
                    guard let size = attrs.fileSize, size <= WebCapture.maxBytes else { throw WebCapture.ImportError.tooLarge }
                    return try WebCapture.decode(Data(contentsOf: file))
                }) {
                    result.imported.append(id)
                }
                try fm.removeItem(at: file)
            } catch { result.failures.append(file.lastPathComponent) }
        }
        return result
    }
}
