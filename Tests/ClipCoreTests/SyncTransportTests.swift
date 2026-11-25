import XCTest
@testable import ClipCore

private actor MemoryRevisionTransport: RevisionTransport {
    var account: SyncAccount
    var revisions: [UUID: SyncRevision] = [:]
    var writes = 0
    init(_ account: SyncAccount) { self.account = account }
    func identity() -> SyncAccount { account }
    func changeAccount(_ account: SyncAccount) { self.account = account }
    func fetchRevisions(expected: SyncAccount) throws -> [SyncRevision] {
        guard expected == account else { throw SyncExchange.ExchangeError.accountChanged }
        return Array(revisions.values)
    }
    func upload(_ incoming: [SyncRevision], expected: SyncAccount) throws {
        guard expected == account else { throw SyncExchange.ExchangeError.accountChanged }
        for r in incoming {
            if let existing = revisions[r.id] {
                guard existing == r else { throw SyncJournal.JournalError.conflictingIdentity }
                continue
            }
            guard r.parents.isSubset(of: Set(revisions.keys)) else { throw SyncJournal.JournalError.missingParent }
            revisions[r.id] = r
            writes += 1
        }
    }
}
final class SyncTransportTests: XCTestCase {
    func testExchangeAndRetryAcrossTwoDevices() async throws {
        let account = SyncAccount(provider:"fake",namespace:"test",accountID:"a")
        let remote = MemoryRevisionTransport(account)
        let note = Note(title:"Mac",parts:[.init(text:"hello")])
        var a = try SyncJournal.bootstrap(NoteLibrary(notes:[note]))
        var updated = note; updated.title = "Mac edited"
        try a.record(.note(updated),for:.note(note.id))
        let plan = try await SyncExchange.prepare(local:a,transport:remote,expected:account)
        XCTAssertEqual(plan.outgoing.count,2)
        try await SyncExchange.send(plan,transport:remote,expected:account)
        try await SyncExchange.send(plan,transport:remote,expected:account)
        let writes = await remote.writes
        XCTAssertEqual(writes,2)
        var phone = SyncJournal()
        let download = try await SyncExchange.prepare(local:phone,transport:remote,expected:account)
        try phone.ingest(download.remote)
        XCTAssertEqual(phone,a)
        XCTAssertTrue(download.outgoing.isEmpty)
    }
    func testAccountChangeBlocksUpload() async throws {
        let account = SyncAccount(provider:"fake",namespace:"test",accountID:"a")
        let remote = MemoryRevisionTransport(account)
        let journal = try SyncJournal.bootstrap(NoteLibrary(notes:[Note(title:"local",parts:[.init(text:"private")])]))
        let plan = try await SyncExchange.prepare(local:journal,transport:remote,expected:account)
        await remote.changeAccount(SyncAccount(provider:"fake",namespace:"test",accountID:"b"))
        do { try await SyncExchange.send(plan,transport:remote,expected:account); XCTFail("Unexpected upload") }
        catch { XCTAssertEqual(error as? SyncExchange.ExchangeError,.accountChanged) }
        let writes = await remote.writes
        XCTAssertEqual(writes,0)
    }
    func testInvalidRemoteRejectedBeforeUpload() throws {
        let bad = SyncRevision(key:.note(UUID()),parents:[UUID()],value:.deleted)
        XCTAssertThrowsError(try SyncExchange.plan(local:SyncJournal(),remote:[bad]))
    }
}
