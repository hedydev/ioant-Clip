#if os(macOS) && CLIP_CLOUDKIT_REVIEW && CLIP_CLOUDKIT_SMOKE
import Foundation

enum CloudKitIncrementalSmoke {
    enum Failure: Error { case unexpectedGraph, metricsMismatch, scopeAccepted }
    static func run(config: CloudKitReviewConfiguration, log: (String) -> Void) async throws {
        let zone = CloudKitCrossDeviceFixture.zone
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clip-incremental-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("checkpoint.json")
        func reader() -> CloudKitRevisionTransport {
            .init(containerIdentifier: config.container, environment: config.environment, zoneName: zone, checkpointURL: url)
        }
        let first = reader()
        let account = try await first.identity()
        let baseline = try await first.fetchRevisions(expected: account)
        let graph = try CloudKitCrossDeviceFixture.exactGraph(baseline, extra: [CloudKitCrossDeviceFixture.macEdit, CloudKitCrossDeviceFixture.phoneDelete, CloudKitCrossDeviceFixture.resolution])
        guard let full = await first.lastRead, !full.usedCursor, full.downloadedRecords == 7 else { throw Failure.metricsMismatch }
        log("PASS: full fetch 7 records, bytes " + String(full.downloadedBytes))
        let restarted = reader()
        let unchanged = try await restarted.fetchRevisions(expected: account)
        guard Set(unchanged.map(\.id)) == Set(graph.revisions.keys),
              unchanged.allSatisfy({ graph.revisions[$0.id] == $0 }),
              let delta = await restarted.lastRead, delta.usedCursor, delta.downloadedRecords == 0, delta.downloadedBytes == 0 else { throw Failure.metricsMismatch }
        log("PASS: new transport restored durable cursor, 0 records / 0 payload bytes, all 7 retained")
        let note = Note(id: UUID(uuidString: "3D319BFC-1E67-4D52-8C55-CAC278ACD0B1")!, title: "Synthetic incremental fixture", createdAt: Date(timeIntervalSince1970: 1700000000), parts: [.init(text: "Incremental CloudKit test only")])
        let revision = SyncRevision(id: UUID(uuidString: "3D319BFC-1E67-4D52-8C55-CAC278ACD0B2")!, key: .note(note.id), parents: [], value: .note(note))
        let writer = try CloudKitCrossDeviceFixture.transport(config)
        try await writer.upload([revision], expected: account)
        var expected = graph
        try expected.ingest([revision])
        let resumed = reader()
        let changed = try await resumed.fetchRevisions(expected: account)
        guard changed.count == 8, changed.allSatisfy({ expected.revisions[$0.id] == $0 }),
              let metric = await resumed.lastRead, metric.usedCursor, metric.downloadedRecords == 1 else { throw Failure.metricsMismatch }
        log("PASS: independent writer added 1 record, incremental fetch downloaded 1 / " + String(metric.downloadedBytes) + " bytes, exact 8 retained")
        let last = reader()
        let stable = try await last.fetchRevisions(expected: account)
        guard stable.count == 8, stable.allSatisfy({ expected.revisions[$0.id] == $0 }),
              let metric = await last.lastRead, metric.usedCursor, metric.downloadedRecords == 0 else { throw Failure.metricsMismatch }
        log("PASS: durable cursor persisted again; no duplicate payload downloads")
    }
}
#endif
