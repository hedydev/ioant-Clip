import XCTest
@testable import NoteCore

private actor CycleTransport: RevisionTransport {
    var account: SyncAccount
    var records: [UUID: SyncRevision] = [:]
    var uploads = 0
    var hook: (@Sendable () async -> Void)?
    init(_ account: SyncAccount) { self.account = account }
    func identity() -> SyncAccount { account }
    func setAccount(_ value: SyncAccount) { account = value }
    func setHook(_ value: (@Sendable () async -> Void)?) { hook = value }
    func fetchRevisions(expected: SyncAccount) async throws -> [SyncRevision] {
        guard account == expected else { throw SyncSessionError.accountMismatch }
        if let hook { await hook() }
        return Array(records.values)
    }
    func upload(_ revisions: [SyncRevision], expected: SyncAccount) throws {
        guard account == expected else { throw SyncSessionError.accountMismatch }
        try Task.checkCancellation()
        for revision in revisions {
            if let previous = records[revision.id] {
                guard previous == revision else { throw SyncJournal.JournalError.conflictingIdentity }
            } else {
                guard revision.parents.isSubset(of: Set(records.keys)) else { throw SyncJournal.JournalError.missingParent }
                records[revision.id] = revision
                uploads += 1
            }
        }
    }
}
@MainActor private final class CycleLibrary: SyncLibraryAccess {
    var value: NoteLibrary
    var failCommit = false
    var commits = 0
    init(_ value: NoteLibrary) { self.value = value }
    var syncSnapshot: NoteLibrary { value }
    func commitRemoteRevisions(_ revisions: [SyncRevision], account: SyncAccount) throws {
        try value.requireSyncAccount(account)
        guard !failCommit else { throw SyncSessionError.persistenceFailed }
        try value.ingestSyncRevisions(revisions)
        commits += 1
    }
    func add(_ text: String) throws {
        let before = value
        _ = value.add(.init(text: text))
        try value.recordLocalChanges(from: before)
    }
}
final class SyncCycleTests: XCTestCase {
    private let account = SyncAccount(provider:"fake",namespace:"test",accountID:"one")
    func testFirstEnrollmentExcludesDeletedHistoryAndPersistsBinding() throws {
        let deleted = Note(title:"old private",parts:[.init(text:"removed")])
        let live = Note(title:"live",parts:[.init(text:"keep")])
        var library = NoteLibrary(notes:[deleted,live]); try library.initializeSyncJournal()
        let old = library
        library.delete([deleted.id]); try library.recordLocalChanges(from:old)
        let before = library
        XCTAssertThrowsError(try library.enrollSync(account:account,replaceLocalHistory:false))
        XCTAssertEqual(library,before)
        try library.enrollSync(account:account,replaceLocalHistory:true)
        XCTAssertEqual(library.notes,[live])
        XCTAssertEqual(library.syncJournal?.keys,[.note(live.id)])
        try library.setSyncPaused(true,account:account)
        XCTAssertThrowsError(try library.requireSyncAccount(account))
        let other = SyncAccount(provider:"fake",namespace:"test",accountID:"two")
        XCTAssertThrowsError(try library.enrollSync(account:other,replaceLocalHistory:true))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("notes.json")
        try library.save(to:url)
        XCTAssertEqual(try NoteLibrary.load(from:url),library)
    }
    @MainActor func testTwoDeviceCycleAndRetry() async throws {
        let remote = CycleTransport(account)
        var a = NoteLibrary(); try a.enrollSync(account:account,replaceLocalHistory:true)
        var b = NoteLibrary(); try b.enrollSync(account:account,replaceLocalHistory:true)
        let mac = CycleLibrary(a), phone = CycleLibrary(b)
        try mac.add("mac")
        let first = try await SyncCycle().run(library:mac,transport:remote,expected:account)
        XCTAssertEqual(first.uploaded,1)
        let retry = try await SyncCycle().run(library:mac,transport:remote,expected:account)
        XCTAssertEqual(retry.uploaded,0)
        let received = try await SyncCycle().run(library:phone,transport:remote,expected:account)
        XCTAssertEqual(received.downloaded,1)
        XCTAssertEqual(mac.value.notes,phone.value.notes)
        try phone.add("phone")
        _ = try await SyncCycle().run(library:phone,transport:remote,expected:account)
        _ = try await SyncCycle().run(library:mac,transport:remote,expected:account)
        XCTAssertEqual(mac.value.notes,phone.value.notes)
    }
    @MainActor func testEditDuringFetchUsesLatestLibrary() async throws {
        var a = NoteLibrary(); try a.enrollSync(account:account,replaceLocalHistory:true)
        let local = CycleLibrary(a), remote = CycleTransport(account)
        await remote.setHook { await MainActor.run { try! local.add("during fetch") } }
        let result = try await SyncCycle().run(library:local,transport:remote,expected:account)
        XCTAssertEqual(result.uploaded,1)
        XCTAssertEqual(local.value.notes.count,1)
    }
    @MainActor func testPersistenceFailurePreventsUpload() async throws {
        var a = NoteLibrary(); try a.enrollSync(account:account,replaceLocalHistory:true)
        let local = CycleLibrary(a), remote = CycleTransport(account)
        try local.add("local"); local.failCommit = true
        do { _ = try await SyncCycle().run(library:local,transport:remote,expected:account); XCTFail("Unexpected success") }
        catch { XCTAssertEqual(error as? SyncSessionError,.persistenceFailed) }
        let uploads = await remote.uploads
        XCTAssertEqual(uploads,0)
    }
    @MainActor func testPauseDuringFetchPreventsCommitAndUpload() async throws {
        let expected = account
        var a = NoteLibrary(); try a.enrollSync(account:expected,replaceLocalHistory:true)
        let local = CycleLibrary(a), remote = CycleTransport(expected)
        try local.add("local")
        await remote.setHook { await MainActor.run { try! local.value.setSyncPaused(true,account:expected) } }
        do { _ = try await SyncCycle().run(library:local,transport:remote,expected:expected); XCTFail("Unexpected success") }
        catch { XCTAssertEqual(error as? SyncSessionError,.paused) }
        XCTAssertEqual(local.commits,0)
        let uploads = await remote.uploads
        XCTAssertEqual(uploads,0)
    }
    @MainActor func testHistoryLimitDoesNotDeleteLocalData() async throws {
        var a = NoteLibrary(); try a.enrollSync(account:account,replaceLocalHistory:true)
        let local = CycleLibrary(a), remote = CycleTransport(account)
        try local.add("large")
        let before = local.value
        do {
            _ = try await SyncCycle().run(library:local,transport:remote,expected:account,limits:.init(revisionCount:0,payloadBytes:100,totalBytes:100))
            XCTFail("Unexpected success")
        } catch { XCTAssertEqual(error as? SyncSessionError,.historyLimit) }
        XCTAssertEqual(local.value,before)
        XCTAssertEqual(local.commits,0)
    }
}
