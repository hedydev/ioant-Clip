import XCTest
@testable import ClipCore

final class NoteLinkTests: XCTestCase {
    func testFindsArchivedLinksWithTheirTextAndMedia() {
        let part = NotePart(html: """
        <a data-source-href="/read?x=1&amp;y=2"><strong>Read&nbsp;me</strong> &#x263A;</a>
        <a href="/illustration"><img alt="Cover" src="data:image/png;base64,AA=="></a>
        <a href="/watch"><video src="data:video/mp4;base64,AA=="></video></a>
        <a href="#notes" title="Notes"></a>
        <a href="mailto:hello@example.com">Contact</a>
        <a href="javascript:alert(1)">Unsafe</a>
        <!-- <a href="/hidden">Hidden</a> -->
        <script>const markup = '<a href="/script">Script</a>';</script>
        """, text: "https://example.com/read?x=1&y=2 https://another.example/item.",
        sourceURL: "https://example.com/book")
        let links = NoteLink.extract(from: [part])
        XCTAssertEqual(links.map(\.url.absoluteString), [
            "https://example.com/read?x=1&y=2", "https://example.com/illustration",
            "https://example.com/watch", "https://example.com/book#notes",
            "mailto:hello@example.com", "https://another.example/item"
        ])
        XCTAssertEqual(links[0].title, "Read me ☺")
        XCTAssertEqual(links[1].title, "Cover")
        XCTAssertEqual(links[1].media.first?.kind, .image)
        XCTAssertEqual(links[2].media.first?.kind, .video)
        XCTAssertEqual(links[3].title, "Notes")
    }

    func testDecodesExportableMediaWithoutChangingBytes() {
        let svg = MediaData(url: "data:image/svg+xml;charset=utf-8,%3Csvg%2F%3E")
        XCTAssertEqual(svg?.mimeType, "image/svg+xml")
        XCTAssertEqual(svg?.bytes, Data("<svg/>".utf8))
        XCTAssertEqual(MediaData(url: "data:audio/mpeg;base64,AAEC")?.bytes, Data([0, 1, 2]))
        XCTAssertEqual(MediaData(url: "data:image/png,%89PNG")?.bytes, Data([137, 80, 78, 71]))
        XCTAssertNil(MediaData(url: "https://example.com/audio.mp3"))
        XCTAssertNil(MediaData(url: "data:image/svg+xml,%3"))
    }
}
