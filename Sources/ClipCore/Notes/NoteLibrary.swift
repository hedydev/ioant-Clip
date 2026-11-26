import Foundation

public struct NoteLibrary: Codable, Equatable, Sendable {
    public private(set) var notes: [Note]
    private var tagPalette: [String: TagColor]?
    public private(set) var syncJournal: SyncJournal?
    public private(set) var syncEnrollment: SyncEnrollment?
    public init(notes: [Note] = []) { self.notes = notes }
    init(storedNotes: [Note], colors: [String: TagColor], journal: SyncJournal, enrollment: SyncEnrollment?) {
        notes = storedNotes
        tagPalette = colors.isEmpty ? nil : colors
        syncJournal = journal
        syncEnrollment = enrollment
    }

    public var allTags: [String] {
        Note.normalizedTags(notes.flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    public func color(for tag: String) -> TagColor {
        tagPalette?[TagColor.key(tag)] ?? .gray
    }
    public mutating func setColor(_ color: TagColor, for tag: String) {
        let key = TagColor.key(tag)
        guard !key.isEmpty else { return }
        if tagPalette == nil { tagPalette = [:] }
        tagPalette?[key] = color
    }
    /// Includes retained colors even if the last note with that tag was removed.
    public var syncColors: [String: TagColor] { tagPalette ?? [:] }
    public mutating func initializeSyncJournal() throws {
        guard syncJournal == nil else { return }
        syncJournal = try SyncJournal.bootstrap(self)
    }
    /// First enrollment starts with live notes, not pre-enrollment deleted
    /// content. Caller must obtain explicit consent to replace local history.
    /// Existing conflicts must be resolved first. The durable caller must save
    /// this entire library atomically before any transfer.
    public mutating func enrollSync(account: SyncAccount, replaceLocalHistory: Bool) throws {
        guard !account.provider.isEmpty, !account.namespace.isEmpty, !account.accountID.isEmpty else { throw SyncSessionError.invalidAccount }
        if let enrollment = syncEnrollment {
            guard enrollment.account == account else { throw SyncSessionError.accountMismatch }
            return
        }
        guard replaceLocalHistory else { throw SyncSessionError.historyConsentRequired }
        guard syncJournal?.conflictKeys.isEmpty != false else { throw SyncSessionError.unresolvedHistory }
        let fresh = try SyncJournal.bootstrap(self)
        syncJournal = fresh
        syncEnrollment = SyncEnrollment(account: account)
    }
    public mutating func setSyncPaused(_ paused: Bool, account: SyncAccount) throws {
        guard var enrollment = syncEnrollment else { throw SyncSessionError.notEnrolled }
        guard enrollment.account == account else { throw SyncSessionError.accountMismatch }
        enrollment.setPaused(paused)
        syncEnrollment = enrollment
    }
    public func requireSyncAccount(_ account: SyncAccount) throws {
        guard let enrollment = syncEnrollment else { throw SyncSessionError.notEnrolled }
        guard enrollment.account == account else { throw SyncSessionError.accountMismatch }
        guard !enrollment.isPaused else { throw SyncSessionError.paused }
        guard syncJournal != nil else { throw SyncSessionError.persistenceFailed }
    }
    /// Record changes in the same value that is atomically saved to notes.json.
    /// The original remains untouched if recording or persistence fails.
    public mutating func recordLocalChanges(from previous: NoteLibrary) throws {
        guard var journal = previous.syncJournal else { return }
        let before = Dictionary(uniqueKeysWithValues: previous.notes.map { ($0.id, $0) })
        let after = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var changes: [(SyncKey, SyncValue)] = []
        for id in Set(before.keys).union(after.keys) where before[id] != after[id] {
            changes.append((.note(id), after[id].map(SyncValue.note) ?? .deleted))
        }
        for key in Set(previous.syncColors.keys).union(syncColors.keys) where previous.syncColors[key] != syncColors[key] {
            changes.append((.tagColor(key), syncColors[key].map(SyncValue.tagColor) ?? .deleted))
        }
        try journal.recordBatch(changes)
        syncJournal = journal
    }
    /// Incoming history is validated before projection. Divergent heads are
    /// retained; a local visible version stays visible until explicit resolution.
    public mutating func ingestSyncRevisions(_ revisions: [SyncRevision]) throws {
        var next = self
        try next.initializeSyncJournal()
        guard var journal = next.syncJournal else { return }
        try journal.ingest(revisions)
        next.project(journal)
        self = next
    }
    public mutating func resolveSyncConflict(_ key: SyncKey, choosing revisionID: UUID) throws {
        guard var journal = syncJournal,
              journal.conflictKeys.contains(key),
              let chosen = journal.heads(for: key).first(where: { $0.id == revisionID })
        else { throw SyncJournal.JournalError.unresolvedConflict }
        try journal.resolve(chosen.value, for: key)
        var next = self
        next.project(journal)
        self = next
    }
    private mutating func project(_ journal: SyncJournal) {
        let result = LibrarySyncProjection.project(notes: notes, colors: syncColors, journal: journal)
        notes = result.notes
        tagPalette = result.colors.isEmpty ? nil : result.colors
        syncJournal = journal
    }
    public func filtered(query: String, filter: TagFilter) -> [Note] {
        notes.filter { $0.matches(query) && filter.includes($0) }
    }
    @discardableResult public mutating func add(_ part: NotePart, title: String? = nil, id: UUID = UUID()) -> UUID? {
        if notes.contains(where: { $0.id == id }) { return id }
        guard !part.isEmpty else { return nil }
        let supplied = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note = Note(id: id, title: supplied.isEmpty ? Note.title(for: part) : String(supplied.prefix(200)), parts: [part]); notes.insert(note, at: 0); return note.id
    }
    @discardableResult public mutating func merge(_ ids: Set<UUID>) -> UUID? {
        let ordered = notes.filter { ids.contains($0.id) }.reversed()
        guard ordered.count >= 2 else { return nil }
        let note = Note(title: "Merged note (\(ordered.count))", tags: ordered.flatMap(\.tags), parts: ordered.flatMap(\.parts))
        notes.insert(note, at: 0); return note.id
    }
    public mutating func delete(_ ids: Set<UUID>) { notes.removeAll { ids.contains($0.id) } }
    public mutating func update(_ id: UUID, title: String, tags: [String]) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { notes[index].title = trimmed }
        notes[index].tags = Note.normalizedTags(tags)
    }
}
