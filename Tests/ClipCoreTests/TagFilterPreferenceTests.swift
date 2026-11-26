import XCTest
@testable import ClipCore

final class TagFilterPreferenceTests: XCTestCase {
    func testRoundTripAndReservedNames() {
        let values: [TagFilter] = [.all, .untagged, .tag("all"), .tag("untagged"), .tag("tag:项目"), .tag("日本語")]
        for value in values { XCTAssertEqual(TagFilter(preference: value.preference), value) }
        XCTAssertEqual(TagFilter(preference: "invalid"), .all)
        XCTAssertEqual(TagFilter(preference: "tag:  "), .all)
    }

    func testVisibleTagsKeepTheFixedAreaBoundedAndPreserveExplicitEmptySelection() {
        let tags = ["AI Chat", "Development", "Music", "Video", "参考", "项目"]
        XCTAssertEqual(VisibleLibraryTags.resolve("", available: tags), Array(tags.prefix(5)))
        XCTAssertEqual(VisibleLibraryTags.resolve("[]", available: tags), [])
        let selection = VisibleLibraryTags.preference(for: ["ai chat", "项目", "missing"])
        XCTAssertEqual(VisibleLibraryTags.resolve(selection, available: tags), ["AI Chat", "项目"])
        let all = VisibleLibraryTags.preference(for: Set(tags.map(TagColor.key)))
        XCTAssertEqual(VisibleLibraryTags.resolve(all, available: tags), Array(tags.prefix(5)))
    }
}
