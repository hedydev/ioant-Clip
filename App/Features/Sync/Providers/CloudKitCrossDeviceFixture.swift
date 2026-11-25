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
    // A deterministic stale edit and concurrent delete, each with the same
    // parent. Fixed IDs allow exact reconciliation without duplicate writes.
    static let editID = UUID(uuidString: "3D319BFC-1E67-4D52-8C55-CAC278ACD0A3")!
    static let deleteID = UUID(uuidString: "3D319BFC-1E67-4D52-8C55-CAC278ACD0A4")!
    static let resolutionID = UUID(uuidString: "3D319BFC-1E67-4D52-8C55-CAC278ACD0A5")!
    static var macEdit: SyncRevision {
        guard case .note(var note) = fixture.value else { preconditionFailure() }
        note.title = "Synthetic Mac edited iPhone note"
        note.tags = ["Synthetic cross-device", "Mac edit"]
        return .init(id: editID, key: .note(noteID), parents: [revisionID], value: .note(note))
    }
    static var phoneDelete: SyncRevision {
        .init(id: deleteID, key: .note(noteID), parents: [revisionID], value: .deleted)
    }
    static var resolution: SyncRevision {
        .init(id: resolutionID, key: .note(noteID), parents: [editID, deleteID], value: .deleted)
    }
    static func exactGraph(_ records: [SyncRevision], extra: [SyncRevision]) throws -> SyncJournal {
        let expected = [fixture] + extra
        let ids = Set(expected.map(\.id))
        let originals = records.filter { !ids.contains($0.id) }
        var graph = try baseline(originals)
        guard records.count == 3 + expected.count,
              Set(records.map(\.id)).count == records.count,
              expected.allSatisfy({ records.contains($0) }) else { throw Failure.unexpectedGraph }
        try graph.ingest(expected)
        return graph
    }
    static func awaitGraph(_ t: any RevisionTransport, account: SyncAccount, extra: [SyncRevision]) async throws -> SyncJournal {
        for attempt in 0..<10 {
            let records = try await t.fetchRevisions(expected: account)
            if records.count == 4 + extra.count { return try exactGraph(records, extra: extra) }
            guard records.count < 4 + extra.count else { throw Failure.unexpectedGraph }
            if attempt < 9 { try await Task.sleep(for: .seconds(2)) }
        }
        throw Failure.propagationTimeout
    }
    static func macModify(config: CloudKitReviewConfiguration, log: (String) -> Void) async throws {
        let t = try transport(config); let account = try await t.identity()
        var graph = try await awaitGraph(t, account: account, extra: [])
        let remote = Array(graph.revisions.values)
        try graph.ingest([macEdit])
        let plan = try SyncExchange.plan(local: graph, remote: remote)
        guard plan.outgoing == [macEdit] else { throw Failure.unexpectedGraph }
        try await SyncExchange.send(plan, transport: t, expected: account)
        _ = try await awaitGraph(t, account: account, extra: [macEdit])
        log("PASS: Mac changed iPhone note title and tags; exact five revisions")
    }
    static func phoneConflict(config: CloudKitReviewConfiguration, log: (String) -> Void) async throws {
        let t = try transport(config); let account = try await t.identity()
        let remote = try await awaitGraph(t, account: account, extra: [macEdit])
        guard remote.heads(for: .note(noteID)) == [macEdit] else { throw Failure.unexpectedGraph }
        log("PASS: iPhone received Mac title/tag edit with original HTML and PNG")
        // Model a local deletion made from the stale parent before reconnect.
        // This is deterministic stale-state testing, not airplane-mode testing.
        var stale = try exactGraph(Array(remote.revisions.values).filter { $0.id != editID }, extra: [])
        try stale.ingest([phoneDelete])
        let plan = try SyncExchange.plan(local: stale, remote: Array(remote.revisions.values))
        guard plan.outgoing == [phoneDelete] else { throw Failure.unexpectedGraph }
        try await SyncExchange.send(plan, transport: t, expected: account)
        let merged = try await awaitGraph(t, account: account, extra: [macEdit, phoneDelete])
        guard merged.conflictKeys == [.note(noteID)],
              Set(merged.heads(for: .note(noteID)).map(\.id)) == [editID, deleteID] else { throw Failure.unexpectedGraph }
        log("PASS: iPhone stale deletion and concurrent Mac edit both preserved")
    }
    static func macResolve(config: CloudKitReviewConfiguration, log: (String) -> Void) async throws {
        let t = try transport(config); let account = try await t.identity()
        var graph = try await awaitGraph(t, account: account, extra: [macEdit, phoneDelete])
        guard graph.conflictKeys == [.note(noteID)] else { throw Failure.unexpectedGraph }
        let remote = Array(graph.revisions.values)
        // Validate the product's explicit conflict resolution semantics before
        // emitting a deterministic fixture with the same parents and value.
        var trial = graph
        guard let generated = try trial.resolve(.deleted, for: .note(noteID)),
              generated.parents == resolution.parents, generated.value == resolution.value,
              trial.conflictKeys.isEmpty else { throw Failure.unexpectedGraph }
        try graph.ingest([resolution])
        let plan = try SyncExchange.plan(local: graph, remote: remote)
        guard plan.outgoing == [resolution] else { throw Failure.unexpectedGraph }
        try await SyncExchange.send(plan, transport: t, expected: account)
        let final = try await awaitGraph(t, account: account, extra: [macEdit, phoneDelete, resolution])
        guard final.conflictKeys.isEmpty, final.heads(for: .note(noteID)) == [resolution] else { throw Failure.unexpectedGraph }
        log("PASS: Mac resolved edit/delete conflict explicitly; all seven revisions retained")
    }
    static func phoneVerifyResolution(config: CloudKitReviewConfiguration, log: (String) -> Void) async throws {
        let t = try transport(config); let account = try await t.identity()
        let final = try await awaitGraph(t, account: account, extra: [macEdit, phoneDelete, resolution])
        guard final.conflictKeys.isEmpty, final.heads(for: .note(noteID)) == [resolution] else { throw Failure.unexpectedGraph }
        log("PASS: iPhone received resolved deletion and preserved all seven revisions")
    }
}
#endif
