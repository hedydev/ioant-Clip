import XCTest
@testable import ClipCore

final class SyncAttemptScheduleTests: XCTestCase {
    func testInitialIdleAndLocalChanges() {
        var schedule = SyncAttemptSchedule()
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(schedule.isDue(at:now,revisionCount:0))
        schedule.succeeded(at:now,confirmedRevisionCount:3)
        XCTAssertFalse(schedule.isDue(at:now.addingTimeInterval(59),revisionCount:3))
        XCTAssertTrue(schedule.isDue(at:now.addingTimeInterval(60),revisionCount:3))
        XCTAssertFalse(schedule.isDue(at:now.addingTimeInterval(14),revisionCount:4))
        XCTAssertTrue(schedule.isDue(at:now.addingTimeInterval(15),revisionCount:4))
        XCTAssertTrue(schedule.isDue(at:now.addingTimeInterval(-1),revisionCount:3))
    }
    func testFailureCancellationAndReset() {
        var schedule = SyncAttemptSchedule()
        let now = Date()
        schedule.succeeded(at:now,confirmedRevisionCount:2)
        schedule.failed(at:now)
        XCTAssertFalse(schedule.isDue(at:now.addingTimeInterval(15),revisionCount:4))
        XCTAssertTrue(schedule.isDue(at:now.addingTimeInterval(60),revisionCount:4))
        schedule.cancelled()
        XCTAssertTrue(schedule.isDue(at:now,revisionCount:4))
        schedule.succeeded(at:now,confirmedRevisionCount:4)
        schedule.reset()
        XCTAssertTrue(schedule.isDue(at:now,revisionCount:4))
    }
}
