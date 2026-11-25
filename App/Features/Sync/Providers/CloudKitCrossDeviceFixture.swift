#if CLIP_CLOUDKIT_REVIEW && (CLIP_CLOUDKIT_SMOKE || CLIP_CLOUDKIT_SIM_SMOKE)
import Foundation
import CloudKit

/// Fixed synthetic fixture; only the previously verified smoke zone is eligible.
enum CloudKitCrossDeviceFixture {
    static let zone = "ioantClipSmoke-25CD4088-61CC-4D56-9D83-0E0641B8737F"
    enum Failure: Error { case configuration, unexpectedGraph, propagationTimeout }
    static let noteID = UUID(uuidString: "3D319BFC-1E67-4D52-8C55-CAC278ACD0A1")!
    static let revisionID = UUID(uuidString: "3D319BFC-1E67-4D52-8C55-CAC278ACD0A2")!
    static var fixture: SyncRevision {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jH0cAAAAASUVORK5CYII=")!
        let note = Note(id: noteID, title: "Synthetic iPhone CloudKit fixture",
                        createdAt: Date(timeIntervalSince1970: 1700000000), tags: ["Synthetic cross-device"],
                        parts: [.init(html: "<p><strong>Simulator to Mac</strong></p>", text: "Simulator to Mac"),
                                .init(image: png, imageMIME: "image/png")])
        return SyncRevision(id: revisionID, key: .note(noteID), parents: [], value: .note(note))
    }
    static func transport(_ config: CloudKitReviewConfiguration) throws -> CloudKitRevisionTransport {
        guard config.container == "iCloud.com.ioant.clip", config.environment == "Development" else { throw Failure.configuration }
        return CloudKitRevisionTransport(containerIdentifier: config.container, environment: config.environment, zoneName: zone)
    }
    static func baseline(_ records: [SyncRevision]) throws -> SyncJournal {
        let original = records.filter { $0.id != revisionID }
        guard original.count == 3, Set(original.map(\.id)).count == 3,
              let initial = original.first(where: { $0.parents.isEmpty }),
              case .note(let note) = initial.value,
              note.title == "Synthetic CloudKit smoke",
              note.plainText == "Generated test fixture; no user content.",
              initial.key == .note(note.id), note.id != noteID,
              let edited = original.first(where: { $0.parents == [initial.id] }),
              case .note(let edit) = edited.value,
              edit.id == note.id, edit.title == "Synthetic CloudKit smoke edited",
              edit.plainText == note.plainText,
              original.contains(where: { $0.key == initial.key && $0.parents == [edited.id] && $0.value == .deleted })
        else { throw Failure.unexpectedGraph }
        var graph = SyncJournal()
        try graph.ingest(original)
        guard graph.heads(for: initial.key).count == 1,
              graph.heads(for: initial.key).first?.value == .deleted else { throw Failure.unexpectedGraph }
        return graph
    }
    static func readBack(_ transport: any RevisionTransport, account: SyncAccount) async throws {
        for attempt in 0..<10 {
            let records = try await transport.fetchRevisions(expected: account)
            _ = try baseline(records)
            if records.count == 4, records.filter({ $0.id == revisionID }) == [fixture] { return }
            guard records.count == 3 else { throw Failure.unexpectedGraph }
            if attempt < 9 { try await Task.sleep(for: .seconds(2)) }
        }
        throw Failure.propagationTimeout
    }
    static func runSimulator(config: CloudKitReviewConfiguration, log: (String) -> Void) async throws {
        let t = try transport(config)
        let account = try await t.identity()
        log("PASS: simulator CloudKit identity available")
        let remote = try await t.fetchRevisions(expected: account)
        var graph = try baseline(remote)
        guard remote.count == 3 || (remote.count == 4 && remote.filter({ $0.id == revisionID }) == [fixture]) else { throw Failure.unexpectedGraph }
        log("PASS: iPhone independently read exact Mac-created three-revision graph")
        try graph.ingest([fixture])
        let plan = try SyncExchange.plan(local: graph, remote: remote)
        guard plan.outgoing == (remote.count == 3 ? [fixture] : []) else { throw Failure.unexpectedGraph }
        try await SyncExchange.send(plan, transport: t, expected: account)
        try await readBack(t, account: account)
        log("PASS: iPhone synthetic rich text, tag and PNG uploaded and read back")
    }
    static func verifyMac(config: CloudKitReviewConfiguration, log: (String) -> Void) async throws {
        let t = try transport(config)
        let account = try await t.identity()
        try await readBack(t, account: account)
        log("PASS: Mac independently read exact iPhone synthetic rich text, tag and PNG; four-revision graph")
    }
}
#endif
