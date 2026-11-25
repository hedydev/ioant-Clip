import Foundation

/// Durable handoff from the local browser host. Only UUID-named regular files
/// are consumed, and files remain until the library has been saved.
public enum CaptureInbox {
    public struct Result: Equatable {
        public var imported: [UUID] = []
        public var failures: [String] = []
    }
    public static func drain(directory: URL, libraryURL: URL, library: inout NoteLibrary) throws -> Result {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return Result() }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey]
        let pending = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
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
                if library.notes.contains(where: { $0.id == id }) {
                    try fm.removeItem(at: file)
                    continue
                }
                guard let size = attrs.fileSize, size <= WebCapture.maxBytes else { throw WebCapture.ImportError.tooLarge }
                let capture = try WebCapture.decode(Data(contentsOf: file))
                var next = library
                guard next.add(capture.part, title: capture.title, id: id) != nil else { throw WebCapture.ImportError.empty }
                try next.recordLocalChanges(from: library)
                try next.save(to: libraryURL)
                library = next
                result.imported.append(id)
                try fm.removeItem(at: file)
            } catch { result.failures.append(file.lastPathComponent) }
        }
        return result
    }
}
