import XCTest
@testable import ClipCore

final class StoragePresentationTests: XCTestCase {
    private let account = SyncAccount(provider: "icloud", namespace: "test", accountID: "test")
    private func state(_ enrollment: SyncEnrollment? = nil, _ activity: StoragePresentation.Activity = .idle,
                       available: Bool = true, conflicts: Bool = false, success: Bool = false) -> StoragePresentation {
        .init(enrollment: enrollment, activity: activity, available: available, hasConflicts: conflicts, hadSuccess: success)
    }
    func testLocalAndPendingConnectionDoNotClaimCloudStorage() {
        XCTAssertEqual(state().provider, .local)
        XCTAssertEqual(state().state, .local)
        XCTAssertEqual(state(nil, .checking).provider, .local)
        XCTAssertEqual(state(nil, .checking).state, .checking)
        XCTAssertEqual(state(nil, .failed).state, .error)
    }
    func testEnrollmentAndActualSessionActivity() {
        let linked = SyncEnrollment(account: account)
        XCTAssertEqual(state(linked).provider, .iCloud)
        XCTAssertEqual(state(linked).state, .linked)
        XCTAssertEqual(state(linked, .syncing).state, .syncing)
        XCTAssertEqual(state(linked, .failed, success: true).state, .error)
        XCTAssertEqual(state(linked, success: true).state, .lastSuccess)
        XCTAssertEqual(state(linked, conflicts: true, success: true).state, .conflicts)
        XCTAssertEqual(state(linked, available: false, success: true).state, .unavailable)
    }
    func testPausedBindingAndUnsupportedProviderRemainVisible() {
        let paused = SyncEnrollment(account: account, isPaused: true)
        XCTAssertEqual(state(paused).provider, .iCloud)
        XCTAssertEqual(state(paused, success: true).state, .paused)
        let drive = SyncEnrollment(account: .init(provider: "google-drive", namespace: "test", accountID: "test"))
        XCTAssertEqual(state(drive).provider, .googleDrive)
        XCTAssertEqual(state(drive).state, .unavailable)
    }
}
