#if os(macOS) && CLIP_CLOUDKIT_REVIEW && CLIP_CLOUDKIT_SMOKE
import Foundation

/// Exercises the exact LibraryStore and CloudSyncController used by SwiftUI,
/// with synthetic data, isolated paths and a never-before-used test zone.
@MainActor enum CloudKitControllerSmoke {
    enum Failure: Error { case scope, local, consent, connected, paused, resumed, receiver, unexpectedHistory }
    static func run(config: CloudKitReviewConfiguration, log: (String) -> Void) async throws {
        guard config.container == "iCloud.com.ioant.clip", config.environment == "Development" else { throw Failure.scope }
        let zone = "ioantClipControllerSmoke-20261126-01"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(zone, isDirectory: true)
        // A prior attempt may have written data: stop, never automatically repeat.
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw Failure.scope }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        log("Synthetic controller zone: " + zone)
        func reader(_ name: String) -> CloudKitRevisionTransport {
            CloudKitRevisionTransport(containerIdentifier: config.container, environment: config.environment, zoneName: zone,
                checkpointURL: directory.appendingPathComponent(name + "-checkpoint.json"))
        }
        func controller(_ name: String) -> CloudSyncController {
            CloudSyncController(testConfiguration: config, testTransport: { reader(name) })
        }
        let independent = reader("observer")
        let account = try await independent.identity()
        guard try await independent.fetchRevisions(expected: account).isEmpty else { throw Failure.unexpectedHistory }
        let url = directory.appendingPathComponent("sender.json")
        let sender = LibraryStore(url: url)
        let first = controller("sender")
        guard sender.error == nil, sender.library.syncEnrollment == nil,
              let note = sender.change({ $0.add(.init(text: "Synthetic controller integration"), title: "Controller test") }) ?? nil else { throw Failure.local }
        await first.prepareEnrollment(store: sender)
        guard first.pendingAccount == account, sender.library.syncEnrollment == nil else { throw Failure.consent }
        first.cancelEnrollment()
        guard first.pendingAccount == nil, sender.library.syncEnrollment == nil,
              try await independent.fetchRevisions(expected: account).isEmpty else { throw Failure.consent }
        log("PASS: connect check and cancel did not enroll or upload")
        await first.prepareEnrollment(store: sender)
        guard let approval = first.approveEnrollment(store: sender) else { throw Failure.consent }
        await approval.value
        guard first.phase == .idle, first.lastSuccess != nil, sender.library.syncEnrollment?.account == account,
              sender.library.syncJournal?.revisions.count == 1,
              try NoteLibrary.load(from: url) == sender.library else { throw Failure.connected }
        let initial = try await independent.fetchRevisions(expected: account)
        guard initial.count == 1, initial.first?.key == .note(note) else { throw Failure.connected }
        log("PASS: explicit approval persisted enrollment and uploaded one synthetic note")
        first.setPaused(true, store: sender)
        guard sender.library.syncEnrollment?.isPaused == true,
              sender.change({ $0.update(note, title: "Changed while paused", tags: ["Synthetic"]) ; return true }) == true else { throw Failure.paused }
        await first.syncNow(store: sender)
        await first.syncIfDue(store: sender)
        guard try NoteLibrary.load(from: url) == sender.library,
              Set(try await independent.fetchRevisions(expected: account).map(\.id)) == Set(initial.map(\.id)) else { throw Failure.paused }
        log("PASS: pause blocks manual and scheduled upload; local edit durable")
        let reopened = LibraryStore(url: url)
        let resumed = controller("sender")
        guard reopened.library.syncEnrollment?.isPaused == true, reopened.library.notes.first?.title == "Changed while paused" else { throw Failure.paused }
        resumed.setPaused(false, store: reopened)
        await resumed.syncNow(store: reopened)
        guard resumed.phase == .idle, resumed.lastSuccess != nil, reopened.library.syncEnrollment?.isPaused == false,
              try NoteLibrary.load(from: url) == reopened.library else { throw Failure.resumed }
        let final = try await independent.fetchRevisions(expected: account)
        guard final.count == 2, final.allSatisfy({ reopened.library.syncJournal?.revisions[$0.id] == $0 }) else { throw Failure.resumed }
        log("PASS: reopened local library resumed, uploaded exactly one pending edit")
        let receiverURL = directory.appendingPathComponent("receiver.json")
        let receiver = LibraryStore(url: receiverURL)
        let receiving = controller("receiver")
        await receiving.prepareEnrollment(store: receiver)
        guard let receiveApproval = receiving.approveEnrollment(store: receiver) else { throw Failure.receiver }
        await receiveApproval.value
        guard receiving.phase == .idle, receiving.lastSuccess != nil,
              receiver.library.notes == reopened.library.notes,
              receiver.library.syncJournal == reopened.library.syncJournal,
              try NoteLibrary.load(from: receiverURL) == receiver.library else { throw Failure.receiver }
        log("PASS: independent app controller received and persisted same note, title and tags")
        log("PASS: controller integration complete; synthetic local and cloud history retained")
    }
}
#endif
