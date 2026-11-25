import Foundation
import SwiftUI
import OSLog

@MainActor final class LibraryStore: ObservableObject, SyncLibraryAccess {
    @Published private(set) var library = NoteLibrary()
    @Published var error: LibraryIssue?
    private let url: URL
    private var ready = false
    @Published private(set) var lastIncoming: UUID?
    private var inboxHealth = InboxHealth()
    @Published private(set) var captureInboxIssue: String?
    private let inboxLogger = Logger(subsystem: "com.ioant.clip.capture", category: "inbox")
    init(url: URL = LibraryLocation.notesURL) {
        self.url = url
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
    var syncSnapshot: NoteLibrary { library }
    /// These entry points are not called by unsigned builds. Keep enrollment,
    /// remote projection and notes in the same atomic persistence boundary.
    func enrollSync(account: SyncAccount, replaceLocalHistory: Bool) throws {
        guard ready else { throw SyncSessionError.persistenceFailed }
        var next = library
        try next.enrollSync(account: account, replaceLocalHistory: replaceLocalHistory)
        try next.save(to: url)
        library = next
    }
    func setSyncPaused(_ paused: Bool, account: SyncAccount) throws {
        guard ready else { throw SyncSessionError.persistenceFailed }
        var next = library
        try next.setSyncPaused(paused, account: account)
        try next.save(to: url)
        library = next
    }
    func commitRemoteRevisions(_ revisions: [SyncRevision], account: SyncAccount) throws {
        guard ready else { throw SyncSessionError.persistenceFailed }
        try library.requireSyncAccount(account)
        var next = library
        try next.ingestSyncRevisions(revisions)
        if next != library {
            try next.save(to: url)
            library = next
        }
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
    func receivePendingCaptures() {
        guard ready else { return }
        #if os(macOS)
        drainCaptureInbox(url.deletingLastPathComponent().appending(path: "CaptureInbox"), source: .local)
        #endif
        #if CLIP_CAPTURE_EXTENSIONS
        if !LibraryLocation.isCloudReview {
            if let inbox = SharedCaptureInbox.directory {
                drainCaptureInbox(inbox, source: .shared)
            } else if inboxHealth.isDue(.shared) {
                updateInboxHealth(.shared, state: .unreadable(domain: "AppGroupUnavailable", code: 1))
            }
        }
        #endif
    }
    private func drainCaptureInbox(_ inbox: URL, source: InboxHealth.Source) {
        guard inboxHealth.isDue(source) else { return }
        do {
            var next = library
            let result = try CaptureInbox.drain(directory: inbox, libraryURL: url, library: &next)
            if !result.imported.isEmpty { library = next }
            if let id = result.imported.last { lastIncoming = id }
            updateInboxHealth(source, state: result.failures.isEmpty ? .healthy : .partial(result.failures.count))
        } catch {
            let failure = error as NSError
            updateInboxHealth(source, state: .unreadable(domain: failure.domain, code: failure.code))
        }
    }
    private func updateInboxHealth(_ source: InboxHealth.Source, state: InboxHealth.State) {
        let changed = inboxHealth.update(source, state: state)
        if changed {
            // No capture title, URL, content, file name or account identifier in logs.
            switch state {
            case .healthy: inboxLogger.info("Inbox \(source.rawValue, privacy: .public) readable")
            case .partial(let count): inboxLogger.error("Inbox \(source.rawValue, privacy: .public) retained \(count, privacy: .public) failed files")
            case .unreadable(let domain, let code): inboxLogger.error("Inbox \(source.rawValue, privacy: .public) read failed \(domain, privacy: .public) \(code, privacy: .public)")
            }
        }
        let issue = inboxHealth.hasUnreadable ? "error.inbox.read" : (inboxHealth.hasPartial ? "error.inbox.partial" : nil)
        if captureInboxIssue != issue { captureInboxIssue = issue }
    }
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

