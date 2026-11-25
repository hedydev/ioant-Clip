import Foundation
import SwiftUI

/// One controller per app, shared by windows. An identity check is not consent.
@MainActor final class CloudSyncController: ObservableObject {
    enum Phase: Equatable {
        case idle, checking, syncing, failed(String)
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pendingAccount: SyncAccount?
    @Published private(set) var lastSuccess: Date?
    private let config: CloudKitReviewConfiguration?
    private let makeTransport: () -> any RevisionTransport
    private let cycle = SyncCycle()
    private var schedule = SyncAttemptSchedule()
    init() {
        let config = CloudKitReviewConfiguration.current()
        self.config = config
        self.makeTransport = {
            guard let config else { preconditionFailure("CloudKit configuration unavailable") }
            return config.transport()
        }
    }
    #if CLIP_CLOUDKIT_SMOKE
    // Explicit synthetic lane only; no default library or zone is substituted.
    init(testConfiguration: CloudKitReviewConfiguration, testTransport: @escaping () -> any RevisionTransport) {
        self.config = testConfiguration
        self.makeTransport = testTransport
    }
    #endif
    var available: Bool { config != nil }
    var busy: Bool { phase == .checking || phase == .syncing }

    func prepareEnrollment(store: LibraryStore) async {
        guard !busy, let config, store.library.syncEnrollment == nil else { return }
        pendingAccount = nil
        phase = .checking
        do {
            let account = try await makeTransport().identity()
            try Task.checkCancellation()
            guard account.provider == "icloud", account.namespace == config.namespace else { throw SyncSessionError.accountMismatch }
            pendingAccount = account
            phase = .idle
        } catch { fail(error) }
    }
    func cancelEnrollment() { pendingAccount = nil }
    @discardableResult func approveEnrollment(store: LibraryStore) -> Task<Void, Never>? {
        guard !busy, let account = pendingAccount, config != nil, store.library.syncEnrollment == nil else { return nil }
        pendingAccount = nil
        phase = .checking
        return Task { await confirmEnrollment(account: account, store: store) }
    }
    private func confirmEnrollment(account: SyncAccount, store: LibraryStore) async {
        do {
            let transport = makeTransport()
            guard try await transport.identity() == account else { throw SyncSessionError.accountMismatch }
            try Task.checkCancellation()
            try store.enrollSync(account: account, replaceLocalHistory: true)
            phase = .idle
            await syncNow(store: store)
        } catch { fail(error) }
    }
    func setPaused(_ paused: Bool, store: LibraryStore) {
        guard !busy, let enrollment = store.library.syncEnrollment else { return }
        // Resuming only permits future cycles with the already bound identity.
        do {
            try store.setSyncPaused(paused, account: enrollment.account)
            phase = .idle
            schedule.reset()
        } catch { fail(error) }
    }
    func syncNow(store: LibraryStore) async {
        guard !busy, let config, let enrollment = store.library.syncEnrollment,
              !enrollment.isPaused else { return }
        guard enrollment.account.provider == "icloud", enrollment.account.namespace == config.namespace else {
            fail(SyncSessionError.accountMismatch); return
        }
        phase = .syncing
        do {
            let result = try await cycle.run(library: store, transport: makeTransport(), expected: enrollment.account)
            let completed = Date()
            schedule.succeeded(at: completed, confirmedRevisionCount: result.confirmedRevisionCount)
            lastSuccess = completed
            phase = .idle
        } catch {
            if error is CancellationError || Task.isCancelled { schedule.cancelled() }
            else { schedule.failed(at: Date()) }
            fail(error)
        }
    }
    func syncIfDue(store: LibraryStore) async {
        guard !busy, pendingAccount == nil, available, let enrollment = store.library.syncEnrollment,
              !enrollment.isPaused else { return }
        guard schedule.isDue(at: Date(), revisionCount: store.library.syncJournal?.revisions.count ?? 0) else { return }
        await syncNow(store: store)
    }
    private func fail(_ error: Error) {
        if error is CancellationError || Task.isCancelled { phase = .idle; return }
        switch error {
        case SyncSessionError.accountMismatch, SyncExchange.ExchangeError.accountChanged,
             RemoteRevisionCheckpoint.Failure.scopeMismatch,
             CloudKitRevisionTransport.ProviderError.accountChanged:
            phase = .failed("sync.error.accountChanged")
        case SyncSessionError.historyLimit:
            phase = .failed("sync.error.limit")
        case SyncSessionError.unresolvedHistory:
            phase = .failed("error.sync.conflict")
        case CloudKitRevisionTransport.ProviderError.accountUnavailable:
            phase = .failed("sync.error.accountUnavailable")
        default:
            phase = .failed("sync.error.retry")
        }
    }
}
