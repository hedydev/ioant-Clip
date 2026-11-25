import XCTest
@testable import ClipCore
final class WebCaptureTests: XCTestCase {
    func testImportPreservesSourceAndMarkup() throws {
        let json = #"{"version":1,"title":"Chat","sourceURL":"https://example.com/chat","mode":"page","html":"<b>Answer</b>","text":"Answer","truncated":false}"#
        let capture = try WebCapture.decode(Data(json.utf8))
        var library = NoteLibrary()
        XCTAssertNotNil(library.add(capture.part, title: capture.title))
        XCTAssertEqual(library.notes.first?.title, "Chat")
        XCTAssertEqual(library.notes.first?.parts.first?.sourceURL, "https://example.com/chat")
        XCTAssertEqual(library.notes.first?.parts.first?.html, "<b>Answer</b>")
    }
    func testRejectUnsupportedCapture() {
        let json = #"{"version":2,"title":"Chat","sourceURL":"","mode":"page","html":"<b>Answer</b>","text":"Answer"}"#
        XCTAssertThrowsError(try WebCapture.decode(Data(json.utf8)))
    }
}
