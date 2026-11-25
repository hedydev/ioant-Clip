import XCTest
@testable import ClipCore

final class TagFilterPreferenceTests: XCTestCase {
    func testRoundTripAndReservedNames() {
        let values: [TagFilter] = [.all, .untagged, .tag("all"), .tag("untagged"), .tag("tag:项目"), .tag("日本語")]
        for value in values { XCTAssertEqual(TagFilter(preference: value.preference), value) }
        XCTAssertEqual(TagFilter(preference: "invalid"), .all)
        XCTAssertEqual(TagFilter(preference: "tag:  "), .all)
    }
}
