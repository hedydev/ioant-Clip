#if os(macOS) && CLIP_CLOUDKIT_REVIEW && CLIP_CLOUDKIT_SMOKE
import Foundation
import CloudKit
import Darwin

/// Dedicated signed development executable, not the SwiftUI application.
/// No LibraryStore, local note files, browser inbox, or production zone access.
@main struct CloudKitSmokeMain {
    private enum Failure: Error {
        case invalidConfiguration, unexpectedRemote, propagationTimeout, wrongAccount, wrongPlan
    }
    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
    static func main() async {
        guard CommandLine.arguments == [CommandLine.arguments[0], "--clip-cloudkit-smoke"],
              Bundle.main.object(forInfoDictionaryKey: "ClipCloudKitSmoke") as? String == "YES",
              let config = CloudKitReviewConfiguration.current(),
              config.environment == "Development", config.container == "iCloud.com.ioant.clip" else {
            log("BLOCKED: invalid smoke configuration or missing explicit run argument")
            exit(2)
        }
        let zoneName = "ioantClipSmoke-" + UUID().uuidString
        log("Synthetic development zone: " + zoneName)
        var stage = "account"
        do {
            let first = CloudKitRevisionTransport(containerIdentifier: config.container, environment: config.environment, zoneName: zoneName)
            let second = CloudKitRevisionTransport(containerIdentifier: config.container, environment: config.environment, zoneName: zoneName)
            let account = try await first.identity()
            guard account.provider == "icloud", account.namespace == config.namespace,
                  try await second.identity() == account else { throw Failure.wrongAccount }
            log("PASS: signed private database account available; same identity for both transports")
            stage = "initial upload"
            let note = Note(title: "Synthetic CloudKit smoke", parts: [.init(text: "Generated test fixture; no user content.")])
            var a = try SyncJournal.bootstrap(NoteLibrary(notes: [note]))
            let initial = try await SyncExchange.prepare(local: a, transport: first, expected: account)
            guard initial.remote.isEmpty, initial.outgoing.count == 1 else { throw Failure.wrongPlan }
            try await SyncExchange.send(initial, transport: first, expected: account)
            stage = "idempotent retry and second transport read"
            try await SyncExchange.send(initial, transport: first, expected: account)
            var b = try await waitFor(a, transport: second, account: account)
            log("PASS: initial upload, duplicate retry and independent read")
            stage = "second transport edit"
            var edited = note
            edited.title = "Synthetic CloudKit smoke edited"
            try b.record(.note(edited), for: .note(note.id))
            let edit = try SyncExchange.plan(local: b, remote: Array(a.revisions.values))
            guard edit.outgoing.count == 1 else { throw Failure.wrongPlan }
            try await SyncExchange.send(edit, transport: second, expected: account)
            a = try await waitFor(b, transport: first, account: account)
            log("PASS: edit returned to first transport")
            stage = "delete tombstone"
            try a.record(.deleted, for: .note(note.id))
            let deletion = try SyncExchange.plan(local: a, remote: Array(b.revisions.values))
            guard deletion.outgoing.count == 1 else { throw Failure.wrongPlan }
            try await SyncExchange.send(deletion, transport: first, expected: account)
            let received = try await waitFor(a, transport: second, account: account)
            guard received.heads(for: .note(note.id)).first?.value == .deleted,
                  received.revisions.count == 3 else { throw Failure.unexpectedRemote }
            log("PASS: deletion tombstone and exact three-revision graph")
            log("PASS: real CloudKit Development transport smoke; synthetic zone retained for review")
        } catch {
            if let cloud = error as? CKError {
                log("FAIL: " + stage + "; CKError code " + String(cloud.code.rawValue))
            } else {
                let ns = error as NSError
                log("FAIL: " + stage + "; " + ns.domain + " code " + String(ns.code))
            }
            // Never silently repeat uncertain writes or delete existing zones.
            exit(1)
        }
    }
    private static func waitFor(_ expected: SyncJournal, transport: any RevisionTransport, account: SyncAccount) async throws -> SyncJournal {
        for attempt in 0..<10 {
            try Task.checkCancellation()
            let records = try await transport.fetchRevisions(expected: account)
            guard Set(records.map(\.id)).count == records.count,
                  records.allSatisfy({ expected.revisions[$0.id] == $0 }) else { throw Failure.unexpectedRemote }
            if records.count == expected.revisions.count {
                var received = SyncJournal()
                try received.ingest(records)
                guard received == expected else { throw Failure.unexpectedRemote }
                return received
            }
            if attempt < 9 { try await Task.sleep(for: .seconds(2)) }
        }
        throw Failure.propagationTimeout
    }
}
#endif
