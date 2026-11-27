import Foundation
import SwiftUI
import OSLog

@MainActor final class LibraryStore: ObservableObject, SyncLibraryAccess {
    @Published private(set) var listRevision = 0
    @Published private(set) var enrollment: SyncEnrollment?
    @Published private(set) var tagCounts: [String: Int] = [:]
    @Published private(set) var totalCount = 0
    @Published private(set) var untaggedCount = 0
    @Published private(set) var syncConflictCount = 0
    var hasConflicts: Bool { syncConflictCount > 0 }
    @Published var error: LibraryIssue?
    private var colors: [String: TagColor] = [:]
    private var repository: SQLiteNoteRepository?
    let url: URL
    var library: NoteLibrary { (try? repository?.snapshot()) ?? NoteLibrary() }
    var allTags: [String] { tagCounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    @Published private(set) var revisionCount = 0
    func color(for tag: String) -> TagColor { colors[TagColor.key(tag)] ?? .gray }
    func loadNote(_ id: UUID) async throws -> Note? {
        guard repository != nil else { return nil }
        return try await databaseWork { [url] in
            try SQLiteNoteRepository.readNote(id, legacyURL: url)
        }
    }

    func loadPage(query: String, filter: TagFilter, after: SQLiteNoteRepository.Row?) async throws -> SQLiteNoteRepository.Page {
        try await databaseWork { [url] in
            try SQLiteNoteRepository.readPage(legacyURL: url, query: query, filter: filter, after: after, limit: 40)
        }
    }

    func loadSyncJournal() async throws -> SyncJournal {
        try await databaseWork(priority: .utility) { [url] in
            try SQLiteNoteRepository.readSyncJournal(legacyURL: url)
        }
    }

    func matchesFilter(_ filter: TagFilter, note id: UUID) async throws -> Bool {
        try await databaseWork { [url] in
            try SQLiteNoteRepository.matchesFilter(filter, note: id, legacyURL: url)
        }
    }

    private func databaseWork<Result: Sendable>(priority: TaskPriority = .userInitiated, _ work: @escaping @Sendable () throws -> Result) async throws -> Result {
        let task = Task.detached(priority: priority) {
            try Task.checkCancellation()
            return try work()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func requireSyncAccount(_ account: SyncAccount) throws {
        guard let enrollment else { throw SyncSessionError.notEnrolled }
        guard enrollment.account == account else { throw SyncSessionError.accountMismatch }
        guard !enrollment.isPaused else { throw SyncSessionError.paused }
    }
    @Published private(set) var lastIncoming: UUID?
    private var inboxHealth = InboxHealth()
    @Published private(set) var captureInboxIssue: String?
    private let inboxLogger = Logger(subsystem: "com.ioant.clip.capture", category: "inbox")
    init(url: URL = LibraryLocation.notesURL) {
        self.url = url
        do {
            let database = try SQLiteNoteRepository(legacyURL: url)
            try refresh(database)
            repository = database
        } catch { self.error = LibraryIssue("error.library.open", detail: error.localizedDescription) }
    }

    private func refresh(_ database: SQLiteNoteRepository) throws {
        enrollment = try database.enrollment
        tagCounts = try database.tagCounts()
        colors = try database.colors()
        syncConflictCount = try database.conflictCount
        totalCount = try database.count()
        untaggedCount = try database.count(filter: .untagged)
        revisionCount = try database.revisionCount()
        listRevision += 1
    }

    private func update<T>(_ mutation: (inout NoteLibrary) throws -> T) throws -> T {
        guard let repository else { throw SyncSessionError.persistenceFailed }
        var changed = false
        let result = try repository.modify { library in
            let previous = library
            let value = try mutation(&library)
            changed = previous != library
            return value
        }
        if changed { try refresh(repository) }
        return result
    }

    @discardableResult func change<T>(_ mutation: (inout NoteLibrary) -> T) -> T? {
        do {
            return try update { next in
                let previous = next
                let result = mutation(&next)
                try next.recordLocalChanges(from: previous)
                return result
            }
        } catch { self.error = LibraryIssue(error); return nil }
    }

    var syncSnapshot: NoteLibrary { library }

    func enrollSync(account: SyncAccount, replaceLocalHistory: Bool) throws {
        try update { try $0.enrollSync(account: account, replaceLocalHistory: replaceLocalHistory) }
    }

    func setSyncPaused(_ paused: Bool, account: SyncAccount) throws {
        try update { try $0.setSyncPaused(paused, account: account) }
    }

    func commitRemoteRevisions(_ revisions: [SyncRevision], account: SyncAccount) throws {
        try requireSyncAccount(account)
        try update { try $0.ingestSyncRevisions(revisions) }
    }

    func prepareSync(remote: [SyncRevision], account: SyncAccount, limits: SyncLimits) async throws -> SyncCycle.Preparation {
        try requireSyncAccount(account)
        let prepared = try await databaseWork(priority: .utility) { [url] in
            try SQLiteNoteRepository.prepareSync(legacyURL: url, remote: remote, account: account, limits: limits)
        }
        if prepared.downloaded > 0, let repository { try refresh(repository) }
        return prepared
    }

    func resolveConflict(_ key: SyncKey, revision: UUID) {
        do { try update { try $0.resolveSyncConflict(key, choosing: revision) } }
        catch { self.error = LibraryIssue(error) }
    }

    func receivePendingCaptures() {
        guard repository != nil else { return }
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
        guard inboxHealth.isDue(source), let repository else { return }
        do {
            let result = try CaptureInbox.drain(directory: inbox) { id, read in
                if try repository.contains(id) { return false }
                let capture = try read()
                return try update { next in
                    let previous = next
                    guard next.add(capture.part, title: capture.title, id: id) != nil else {
                        throw WebCapture.ImportError.empty
                    }
                    try next.recordLocalChanges(from: previous)
                    return true
                }
            }
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

