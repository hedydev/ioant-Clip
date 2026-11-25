import XCTest
@testable import ClipCore

final class RemoteRevisionCheckpointTests: XCTestCase {
    private let account = SyncAccount(provider: "icloud", namespace: "dev", accountID: "a")
    func testScopeAndDurableRoundTrip() throws {
        let note = Note(title: "Synthetic", parts: [.init(text: "fixture")])
        let journal = try SyncJournal.bootstrap(NoteLibrary(notes: [note]))
        let checkpoint = RemoteRevisionCheckpoint(account: account, zone: "test", cursor: Data([1]), journal: journal)
        let restored = try JSONDecoder().decode(RemoteRevisionCheckpoint.self, from: JSONEncoder().encode(checkpoint))
        XCTAssertEqual(restored, checkpoint)
        XCTAssertNoThrow(try restored.validate(account: account, zone: "test"))
        XCTAssertThrowsError(try restored.validate(account: account, zone: "other"))
        XCTAssertThrowsError(try restored.validate(account: .init(provider: "icloud", namespace: "dev", accountID: "b"), zone: "test"))
    }
    func testExpiredCursorRefreshMustPreserveHistory() throws {
        let note = Note(title: "Synthetic", parts: [.init(text: "fixture")])
        let journal = try SyncJournal.bootstrap(NoteLibrary(notes: [note]))
        let checkpoint = RemoteRevisionCheckpoint(account: account, zone: "test", cursor: Data([1]), journal: journal)
        var next = journal
        try next.record(.deleted, for: .note(note.id))
        XCTAssertNoThrow(try checkpoint.requirePreserved(in: next))
        XCTAssertThrowsError(try checkpoint.requirePreserved(in: SyncJournal()))
    }
    func testRejectEmptyCursorAndHistoryLimit() throws {
        let note = Note(title: "Synthetic", parts: [.init(text: "fixture")])
        let journal = try SyncJournal.bootstrap(NoteLibrary(notes: [note]))
        XCTAssertThrowsError(try RemoteRevisionCheckpoint(account: account, zone: "test", cursor: Data(), journal: journal).validate(account: account, zone: "test"))
        XCTAssertThrowsError(try RemoteRevisionCheckpoint(account: account, zone: "test", cursor: Data([1]), journal: journal).validate(account: account, zone: "test", limits: .init(revisionCount: 0, payloadBytes: 1024, totalBytes: 1024)))
    }
}
