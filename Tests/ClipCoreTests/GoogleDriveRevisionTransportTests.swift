import XCTest
@testable import ClipCore

private actor DriveFixture: GoogleDriveRevisionAPI {
    var account = "account-a"
    var rows: [GoogleDriveRevisionFile] = []
    var payloads: [String: Data] = [:]
    var incomplete = false
    var uploads = 0
    func accountID() async throws -> String { account }
    func list(prefix: String, pageToken: String?) async throws -> GoogleDriveRevisionPage {
        let start = Int(pageToken ?? "0")!
        let end = min(start + 1, rows.count)
        return .init(files: Array(rows[start..<end]), nextPageToken: end < rows.count ? String(end) : nil, incompleteSearch: incomplete)
    }
    func download(fileID: String, maxBytes: Int) async throws -> Data {
        guard let data = payloads[fileID], data.count <= maxBytes else { throw GoogleDriveRevisionTransport.Failure.invalidRecord }
        return data
    }
    func create(name: String, payload: Data, checksum: String) async throws -> GoogleDriveRevisionFile {
        uploads += 1
        return add(name: name, payload: payload, checksum: checksum)
    }
    @discardableResult func add(name: String, payload: Data, checksum: String) -> GoogleDriveRevisionFile {
        let id = UUID().uuidString
        let file = GoogleDriveRevisionFile(id: id, name: name, size: String(payload.count), appProperties: ["clipSHA256": checksum], sha256Checksum: checksum)
        rows.append(file); payloads[id] = payload; return file
    }
    func setIncomplete() { incomplete = true }
    func changeAccount() { account = "account-b" }
    func removeAll() { rows.removeAll(); payloads.removeAll() }
    func count() -> Int { uploads }
}
final class GoogleDriveRevisionTransportTests: XCTestCase {
    private func fixture() throws -> (SyncRevision, SyncRevision) {
        let note = Note(title: "Synthetic", parts: [.init(text: "Drive test")])
        let first = SyncRevision(key: .note(note.id), parents: [], value: .note(note))
        return (first, SyncRevision(key: first.key, parents: [first.id], value: .deleted))
    }
    func testParentOrderPagingAndIdempotentReplay() async throws {
        let api = DriveFixture()
        let transport = GoogleDriveRevisionTransport(api: api, namespace: "project-test")
        let account = try await transport.identity()
        let (first, second) = try fixture()
        try await transport.upload([second, first], expected: account)
        let other = GoogleDriveRevisionTransport(api: api, namespace: "project-test")
        let received = try await other.fetchRevisions(expected: account)
        XCTAssertEqual(Set(received.map(\.id)), [first.id, second.id])
        try await other.upload([first, second], expected: account)
        let count = await api.count()
        XCTAssertEqual(count, 2)
    }
    func testIdenticalDuplicateAcceptedDivergenceRejected() async throws {
        let api = DriveFixture()
        let transport = GoogleDriveRevisionTransport(api: api, namespace: "project-test")
        let account = try await transport.identity()
        let (first, _) = try fixture()
        let data = try JSONEncoder().encode(first)
        let name = GoogleDriveRevisionTransport.prefix + first.id.uuidString + ".json"
        await api.add(name: name, payload: data, checksum: GoogleDriveRevisionTransport.checksum(data))
        await api.add(name: name, payload: data, checksum: GoogleDriveRevisionTransport.checksum(data))
        let result = try await transport.fetchRevisions(expected: account)
        XCTAssertEqual(result, [first])
        let different = SyncRevision(id: first.id, key: first.key, parents: [], value: .deleted)
        let changed = try JSONEncoder().encode(different)
        await api.add(name: name, payload: changed, checksum: GoogleDriveRevisionTransport.checksum(changed))
        do { _ = try await transport.fetchRevisions(expected: account); XCTFail("collision accepted") }
        catch GoogleDriveRevisionTransport.Failure.immutableCollision {}
    }
    func testIncompleteSearchAndAccountMismatchBlockWrites() async throws {
        let api = DriveFixture()
        let transport = GoogleDriveRevisionTransport(api: api, namespace: "project-test")
        let account = try await transport.identity()
        let (first, _) = try fixture()
        await api.setIncomplete()
        do { try await transport.upload([first], expected: account); XCTFail("incomplete accepted") }
        catch GoogleDriveRevisionTransport.Failure.incompleteListing {}
        await api.changeAccount()
        do { try await transport.upload([first], expected: account); XCTFail("wrong account accepted") }
        catch SyncSessionError.accountMismatch {}
        let count = await api.count()
        XCTAssertEqual(count, 0)
    }
    func testDisappearedHistoryAndInvalidChecksumRejected() async throws {
        let api = DriveFixture()
        let transport = GoogleDriveRevisionTransport(api: api, namespace: "project-test")
        let account = try await transport.identity()
        let (first, _) = try fixture()
        try await transport.upload([first], expected: account)
        await api.removeAll()
        do { _ = try await transport.fetchRevisions(expected: account); XCTFail("history disappeared") }
        catch GoogleDriveRevisionTransport.Failure.historyDisappeared {}
        let data = try JSONEncoder().encode(first)
        await api.add(name: GoogleDriveRevisionTransport.prefix + first.id.uuidString + ".json", payload: data, checksum: String(repeating: "0", count: 64))
        do { _ = try await transport.fetchRevisions(expected: account); XCTFail("bad checksum accepted") }
        catch GoogleDriveRevisionTransport.Failure.invalidRecord {}
    }
}
