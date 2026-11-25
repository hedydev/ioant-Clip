import XCTest
@testable import ClipCore
final class TagTests: XCTestCase {
    func testLegacyLibraryAndSharedColors() throws {
        let data = Data(#"{"notes":[{"id":"00000000-0000-0000-0000-000000000001","title":"old","createdAt":0,"tags":["Work"],"parts":[{"text":"legacy"}]}]}"#.utf8)
        var library = try JSONDecoder().decode(NoteLibrary.self, from: data)
        XCTAssertEqual(library.color(for: "Work"), .gray)
        library.setColor(.blue, for: " work ")
        XCTAssertEqual(library.color(for: "WORK"), .blue)
        XCTAssertEqual(try JSONDecoder().decode(NoteLibrary.self, from: JSONEncoder().encode(library)), library)
        XCTAssertEqual(library.notes.first?.parts.first?.text, "legacy")
    }
    func testDefaultUntaggedSuggestionsAndFilter() throws {
        var library = NoteLibrary()
        let id = try XCTUnwrap(library.add(.init(text: "Monthly listeners", sourceURL: "https://open.spotify.com/artist/123")))
        let note = try XCTUnwrap(library.notes.first)
        XCTAssertTrue(note.tags.isEmpty)
        XCTAssertEqual(TagSuggestions.forNote(note), ["Music"])
        XCTAssertEqual(library.filtered(query: "", filter: .untagged).count, 1)
        library.update(id, title: note.title, tags: ["Music","music"])
        library.setColor(.green, for: "Music")
        XCTAssertEqual(library.allTags, ["Music"])
        XCTAssertEqual(library.filtered(query: "listeners", filter: .tag("music")).count, 1)
        XCTAssertTrue(library.filtered(query: "", filter: .untagged).isEmpty)
        XCTAssertTrue(TagSuggestions.forNote(library.notes[0]).isEmpty)
    }
    func testNoFalseDomainAndExistingTag() {
        let note = Note(title: "SoWhat project", parts: [.init(text: "项目概览", sourceURL: "https://spotify.com.example.test")])
        XCTAssertEqual(TagSuggestions.forNote(note, existingTags: ["SoWhat"]), ["Development", "SoWhat"])
        XCTAssertTrue(TagSuggestions.forNote(Note(title: "hello", parts: [.init(text: "hello")])).isEmpty)
    }
    func testMergeRetainsGlobalTagColor() throws {
        var library = NoteLibrary()
        let a = try XCTUnwrap(library.add(.init(text: "a")))
        let b = try XCTUnwrap(library.add(.init(text: "b")))
        library.update(a, title: "a", tags: ["Work"])
        library.setColor(.orange, for: "work")
        let merged = try XCTUnwrap(library.merge([a,b]))
        XCTAssertEqual(library.notes.first(where: { $0.id == merged })?.tags, ["Work"])
        XCTAssertEqual(library.color(for: "Work"), .orange)
    }
}
