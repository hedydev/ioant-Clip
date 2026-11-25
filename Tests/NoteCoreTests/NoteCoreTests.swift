import XCTest
@testable import NoteCore
final class NoteCoreTests: XCTestCase {
    func testPasteCreatesDistinctItemsAndRejectsEmpty() {
        var library = NoteLibrary()
        XCTAssertNil(library.add(.init(text: "  ")))
        XCTAssertNotEqual(library.add(.init(text: "same")), library.add(.init(text: "same")))
        XCTAssertEqual(library.notes.count, 2)
    }
    func testMergePreservesOriginalsOrderHTMLAndTags() throws {
        var library = NoteLibrary()
        let first = try XCTUnwrap(library.add(.init(html: "<b>one</b>", text: "one")))
        let second = try XCTUnwrap(library.add(.init(text: "two")))
        library.update(first, title: "First", tags: [" Swift ", "swift"])
        library.update(second, title: "Second", tags: ["Web"])
        let merged = try XCTUnwrap(library.merge([first, second]))
        XCTAssertEqual(library.notes.count, 3)
        XCTAssertEqual(library.notes.first?.id, merged)
        XCTAssertEqual(library.notes.first?.parts.map(\.text), ["one", "two"])
        XCTAssertEqual(library.notes.first?.parts.first?.html, "<b>one</b>")
        XCTAssertEqual(library.notes.first?.tags, ["Swift", "Web"])
        library.delete([first, second]); XCTAssertEqual(library.notes.count, 1)
    }
    func testPersistenceAndSearch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.json")
        var library = try NoteLibrary.load(from: url)
        let id = try XCTUnwrap(library.add(.init(text: "hello world")))
        library.update(id, title: "Title", tags: ["SwiftUI"])
        try library.save(to: url)
        XCTAssertEqual(try NoteLibrary.load(from: url), library)
        XCTAssertTrue(library.notes[0].matches("swiftui"))
        XCTAssertTrue(library.notes[0].matches("WORLD"))
    }
    func testEscapingAndSandboxMarkup() {
        let note = Note(title: "test", parts: [.init(text: "<script>bad</script>")])
        XCTAssertTrue(note.htmlDocument.contains("iframe sandbox"))
        XCTAssertTrue(note.htmlDocument.contains("default-src 'none'"))
        XCTAssertTrue(note.parts[0].renderedHTML.contains("&lt;script&gt;"))
    }
    func testImageEmbedding() {
        let part = NotePart(image: Data([1,2,3]), imageMIME: "image/png")
        XCTAssertFalse(part.isEmpty)
        XCTAssertTrue(part.renderedHTML.contains("data:image/png;base64,AQID"))
    }
}
