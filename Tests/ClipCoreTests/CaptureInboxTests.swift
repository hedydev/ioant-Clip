import XCTest
@testable import ClipCore

final class CaptureInboxTests: XCTestCase {
    let fixture = #"{"version":1,"title":"Browser capture","sourceURL":"https://example.com/","mode":"page","html":"<h1>Hello</h1>","text":"Hello"}"#
    func testSharedEnqueueAndDrain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("CaptureInbox")
        let id = try SharedCaptureInbox.enqueue(Data(fixture.utf8), directory: inbox)
        let files = try FileManager.default.contentsOfDirectory(atPath: inbox.path)
        XCTAssertEqual(files, [id.uuidString + ".json"])
        let path = inbox.appendingPathComponent(files[0])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber, 0o600)
        XCTAssertThrowsError(try SharedCaptureInbox.enqueue(Data("invalid".utf8), directory: inbox))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inbox.path), files)
        var library = NoteLibrary()
        let url = root.appendingPathComponent("notes.json")
        XCTAssertEqual(try CaptureInbox.drain(directory: inbox, libraryURL: url, library: &library).imported, [id])
        XCTAssertEqual(try NoteLibrary.load(from: url), library)
        XCTAssertEqual(library.notes.count, 1)
    }
    func testDurableImportAndReplay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("CaptureInbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let libraryURL = root.appendingPathComponent("notes.json")
        let id = UUID(), file = inbox.appendingPathComponent(id.uuidString + ".json")
        try Data(fixture.utf8).write(to: file)
        var library = NoteLibrary()
        XCTAssertEqual(try CaptureInbox.drain(directory: inbox, libraryURL: libraryURL, library: &library).imported, [id])
        XCTAssertEqual(try NoteLibrary.load(from: libraryURL), library)
        XCTAssertEqual(library.notes.first?.parts.first?.html, "<h1>Hello</h1>")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try Data(fixture.utf8).write(to: file)
        XCTAssertTrue(try CaptureInbox.drain(directory: inbox, libraryURL: libraryURL, library: &library).imported.isEmpty)
        XCTAssertEqual(library.notes.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testMissingAndNonDirectoryInbox() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("CaptureInbox")
        var library = NoteLibrary()
        let url = root.appendingPathComponent("notes.json")
        XCTAssertTrue(try CaptureInbox.drain(directory: inbox,libraryURL:url,library:&library).imported.isEmpty)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try Data("not a directory".utf8).write(to:inbox)
        XCTAssertThrowsError(try CaptureInbox.drain(directory:inbox,libraryURL:url,library:&library))
    }
    func testInvalidAndFailedSaveRetainFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID(), file = root.appendingPathComponent(id.uuidString + ".json")
        let bad = root.appendingPathComponent(UUID().uuidString + ".json")
        try Data(fixture.utf8).write(to: file); try Data("bad".utf8).write(to: bad)
        var library = NoteLibrary()
        // Writing onto a directory fails without committing the in-memory note.
        let result = try CaptureInbox.drain(directory: root, libraryURL: root, library: &library)
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertTrue(library.notes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bad.path))
    }
}
