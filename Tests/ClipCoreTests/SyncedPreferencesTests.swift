import XCTest
@testable import ClipCore

final class SyncedPreferencesTests: XCTestCase {
    func testFirstSyncAdoptsCloudPreferencesAndLaterMergesOnlyEditedFields() {
        let local = SyncedPreferences(language: "zh-Hans", appearance: "system", accent: "blue")
        let remote = SyncedPreferences(language: "en", appearance: "dark", accent: "green")
        XCTAssertEqual(local.merging(remote: remote, lastSynced: nil), remote)

        let prior = SyncedPreferences(language: "en", appearance: "system", accent: "blue")
        XCTAssertEqual(local.merging(remote: remote, lastSynced: prior),
                       SyncedPreferences(language: "zh-Hans", appearance: "dark", accent: "green"))
    }
}
