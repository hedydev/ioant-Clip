import Foundation
import SwiftUI

@MainActor final class LibraryStore: ObservableObject {
    @Published private(set) var library = NoteLibrary()
    @Published var error: LibraryIssue?
    private let url = URL.applicationSupportDirectory.appending(path: "ioant-Note/notes.json")
    private var ready = false
    @Published private(set) var lastIncoming: UUID?
    private var reportedInboxFailures = Set<String>()
    init() {
        do {
            var loaded = try NoteLibrary.load(from: url)
            if loaded.syncJournal == nil {
                try loaded.initializeSyncJournal()
                try loaded.save(to: url)
            }
            library = loaded
            ready = true
        }
        catch { self.error = LibraryIssue("error.library.open", detail: error.localizedDescription) }
    }
    @discardableResult func change<T>(_ mutation: (inout NoteLibrary) -> T) -> T? {
        guard ready else { error = LibraryIssue("error.library.unavailable"); return nil }
        var next = library; let result = mutation(&next)
        do {
            try next.recordLocalChanges(from: library)
            try next.save(to: url)
            library = next
            return result
        }
        catch { self.error = LibraryIssue(error); return nil }
    }
    func resolveConflict(_ key: SyncKey, revision: UUID) {
        guard ready else { return }
        var next = library
        do {
            try next.resolveSyncConflict(key, choosing: revision)
            try next.save(to: url)
            library = next
        } catch { self.error = LibraryIssue(error) }
    }
    #if os(macOS)
    func receivePendingCaptures() {
        guard ready else { return }
        let inbox = url.deletingLastPathComponent().appending(path: "CaptureInbox")
        do {
            var next = library
            let result = try CaptureInbox.drain(directory: inbox, libraryURL: url, library: &next)
            if !result.imported.isEmpty { library = next }
            if let id = result.imported.last { lastIncoming = id }
            let newFailures = Set(result.failures).subtracting(reportedInboxFailures)
            if !newFailures.isEmpty { error = LibraryIssue("error.inbox.partial") }
            reportedInboxFailures = Set(result.failures)
        } catch {
            if reportedInboxFailures.insert("directory").inserted { self.error = LibraryIssue("error.inbox.read") }
        }
    }
    #endif
    func importFile(_ url: URL) -> UUID? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= WebCapture.maxBytes else { throw WebCapture.ImportError.tooLarge }
            let capture = try WebCapture.decode(Data(contentsOf: url))
            let id = change { $0.add(capture.part, title: capture.title) } ?? nil
            if capture.truncated == true, id != nil { error = LibraryIssue("error.capture.truncated") }
            return id
        } catch { self.error = LibraryIssue(error); return nil }
    }
}

