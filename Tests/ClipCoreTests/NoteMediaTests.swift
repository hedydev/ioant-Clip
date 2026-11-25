import XCTest
@testable import ClipCore

final class NoteMediaTests: XCTestCase {
    func testExtractsEmbeddedAndLinkedMediaFromSavedFragments() {
        let html = """
        <img alt="A &amp; B" src="data:image/png;base64,AA==">
        <img src='data:image/svg+xml;base64,AA=='>
        <span hidden data-ioant-media="video" data-ioant-media-src="/movie.mp4?x=1&amp;y=2"></span>
        <audio controls src="data:audio/mpeg;base64,AA=="></audio>
        <!-- <img src="https://example.com/comment.png"> -->
        <img src="javascript:alert(1)">
        """
        let part = NotePart(html: html, sourceURL: "https://example.com/story")
        let items = NoteMedia.extract(from: [part, part])
        XCTAssertEqual(items.map(\.kind), [.image, .svg, .video, .audio])
        XCTAssertEqual(items.first?.title, "A & B")
        XCTAssertEqual(items.first(where: { $0.kind == .video })?.source?.absoluteString,
                       "https://example.com/movie.mp4?x=1&y=2")
        XCTAssertNil(items.first(where: { $0.kind == .video })?.previewDocument)
        XCTAssertTrue(items.last?.previewDocument?.contains("<audio controls") == true)
    }

    func testExtractsPastedImageAndUsesPageForUnavailableMedia() {
        let items = NoteMedia.extract(from: [
            NotePart(image: Data([0]), imageMIME: "image/png"),
            NotePart(html: "<span data-ioant-media='video'></span>", sourceURL: "https://example.com/story"),
        ])
        XCTAssertEqual(items.map(\.kind), [.image, .video])
        XCTAssertEqual(items.last?.source?.absoluteString, "https://example.com/story")
    }
}
