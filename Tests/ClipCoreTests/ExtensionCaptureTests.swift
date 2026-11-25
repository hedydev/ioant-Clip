import XCTest
@testable import ClipCore

final class ExtensionCaptureTests: XCTestCase {
    func testSafariPingAndQueueImport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("CaptureInbox")
        let ping = SafariCaptureBridge.respond(["version":1,"action":"ping"], inbox: inbox, evidenceDirectory: root, language: "zh-Hans")
        XCTAssertEqual(ping["state"] as? String, "reachable")
        XCTAssertEqual(ping["language"] as? String, "zh-Hans")
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
        XCTAssertEqual(SharedExtensionEvidence.read(.safari, directory: root)?.activity, .ping)
        let bad = SafariCaptureBridge.respond(["version":1,"action":"capture","capture":["version":2]], inbox: inbox, evidenceDirectory: root, language: nil)
        XCTAssertEqual(bad["ok"] as? Bool, false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
        let payload: [String: Any] = ["version":1,"title":"Synthetic Safari","sourceURL":"https://example.com/","mode":"selection","html":"<b>Example</b>","text":"Example"]
        let reply = SafariCaptureBridge.respond(["version":1,"action":"capture","capture":payload], inbox: inbox, evidenceDirectory: root, language: nil)
        XCTAssertEqual(reply["state"] as? String, "queued")
        let id = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(reply["id"] as? String)))
        XCTAssertEqual(SharedExtensionEvidence.read(.safari, directory: root)?.activity, .queued)
        var library = NoteLibrary()
        let url = root.appendingPathComponent("notes.json")
        XCTAssertEqual(try CaptureInbox.drain(directory: inbox, libraryURL: url, library: &library).imported,[id])
        XCTAssertEqual(try NoteLibrary.load(from: url),library)
        XCTAssertEqual(library.notes.first?.parts.first?.html,"<b>Example</b>")
        XCTAssertNil(library.syncEnrollment)
    }
    func testSharedTextURLAndImage() throws {
        var composer = ShareCaptureComposer()
        try composer.addText("Example <script>")
        try composer.addText("Example <script>")
        try composer.addURL(URL(string: "https://example.com/")!)
        try composer.addURL(URL(string: "https://example.com/")!)
        let png = Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jR2QAAAAASUVORK5CYII=")!
        try composer.addPNG(png)
        let value = try WebCapture.decode(composer.envelope())
        XCTAssertEqual(value.text,"Example <script>\nhttps://example.com/")
        XCTAssertEqual(value.sourceURL,"https://example.com/")
        XCTAssertTrue(value.html.contains("&lt;script&gt;"))
        XCTAssertTrue(value.html.contains(png.base64EncodedString()))
        XCTAssertThrowsError(try composer.addPNG(png))
        XCTAssertThrowsError(try composer.addURL(URL(fileURLWithPath:"/example")))
    }
    func testShareQueueAndEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var composer = ShareCaptureComposer()
        XCTAssertThrowsError(try composer.envelope())
        try composer.addText("Synthetic share")
        let inbox = root.appendingPathComponent("CaptureInbox")
        let id = try SharedCaptureInbox.enqueue(composer.envelope(),directory:inbox)
        XCTAssertThrowsError(try SharedExtensionEvidence.record(.share,activity:.ping,directory:root))
        try SharedExtensionEvidence.record(.share,activity:.queued,directory:root)
        XCTAssertEqual(SharedExtensionEvidence.read(.share,directory:root)?.activity,.queued)
        XCTAssertNil(SharedExtensionEvidence.read(.safari,directory:root))
        var library = NoteLibrary()
        let url = root.appendingPathComponent("notes.json")
        XCTAssertEqual(try CaptureInbox.drain(directory:inbox,libraryURL:url,library:&library).imported,[id])
        XCTAssertEqual(try NoteLibrary.load(from:url),library)
        XCTAssertNil(library.syncEnrollment)
    }
}
