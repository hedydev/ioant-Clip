import XCTest
@testable import ClipCore

final class InboxHealthTests: XCTestCase {
    func testIndependentInboxFailuresAndRecovery() {
        var health = InboxHealth()
        let now = Date(timeIntervalSince1970: 1000)
        let denied = InboxHealth.State.unreadable(domain: "NSCocoaErrorDomain",code:257)
        XCTAssertTrue(health.update(.shared,state:denied,now:now))
        for i in 1...14 {
            XCTAssertTrue(health.isDue(.local,now:now.addingTimeInterval(Double(i))))
            health.update(.local,state:.healthy,now:now.addingTimeInterval(Double(i)))
            XCTAssertTrue(health.hasUnreadable)
            XCTAssertFalse(health.isDue(.shared,now:now.addingTimeInterval(Double(i))))
        }
        XCTAssertTrue(health.isDue(.shared,now:now.addingTimeInterval(15)))
        XCTAssertFalse(health.update(.shared,state:denied,now:now.addingTimeInterval(15)))
        XCTAssertTrue(health.hasUnreadable)
        XCTAssertTrue(health.update(.shared,state:.healthy,now:now.addingTimeInterval(30)))
        XCTAssertFalse(health.hasUnreadable)
        XCTAssertFalse(health.hasPartial)
    }
    func testPartialFailureDoesNotClearAnotherInbox() {
        var health = InboxHealth()
        health.update(.local,state:.partial(1))
        health.update(.shared,state:.healthy)
        XCTAssertTrue(health.hasPartial)
        health.update(.local,state:.healthy)
        XCTAssertFalse(health.hasPartial)
    }
}
