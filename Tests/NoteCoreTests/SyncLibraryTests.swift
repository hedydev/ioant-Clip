import XCTest
@testable import NoteCore

final class SyncLibraryTests: XCTestCase {
    func testAtomicMigrationAndLocalChanges() throws {
        let n = Note(title:"existing",parts:[.init(text:"text")])
        var library = NoteLibrary(notes:[n])
        try library.initializeSyncJournal()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("notes.json")
        let before = library
        library.update(n.id,title:"edited",tags:["Work"])
        library.setColor(.blue,for:"Work")
        try library.recordLocalChanges(from:before)
        try library.save(to:url)
        XCTAssertEqual(try NoteLibrary.load(from:url),library)
        XCTAssertEqual(library.syncJournal?.heads(for:.note(n.id)).first?.value,.note(library.notes[0]))
        XCTAssertEqual(library.syncJournal?.heads(for:.tagColor("work")).first?.value,.tagColor(.blue))
        let edited = library
        library.delete([n.id])
        try library.recordLocalChanges(from:edited)
        XCTAssertEqual(library.syncJournal?.heads(for:.note(n.id)).first?.value,.deleted)
        XCTAssertTrue(library.notes.isEmpty)
    }
    func testTwoDevicesMergeAndResolve() throws {
        let n = Note(title:"original",parts:[.init(text:"original")])
        var a = NoteLibrary(notes:[n])
        try a.initializeSyncJournal()
        var b = a
        let base = a
        a.update(n.id,title:"Mac",tags:[])
        b.update(n.id,title:"iPhone",tags:[])
        try a.recordLocalChanges(from:base)
        try b.recordLocalChanges(from:base)
        try a.ingestSyncRevisions(Array(try XCTUnwrap(b.syncJournal).revisions.values))
        try b.ingestSyncRevisions(Array(try XCTUnwrap(a.syncJournal).revisions.values))
        XCTAssertEqual(a.notes.first?.title,"Mac")
        XCTAssertEqual(b.notes.first?.title,"iPhone")
        XCTAssertEqual(a.syncJournal?.conflictKeys,[.note(n.id)])
        var blocked = a
        blocked.delete([n.id])
        XCTAssertThrowsError(try blocked.recordLocalChanges(from:a))
        let chosen = try XCTUnwrap(a.syncJournal?.heads(for:.note(n.id)).first { $0.value == .note(b.notes[0]) })
        try a.resolveSyncConflict(.note(n.id),choosing:chosen.id)
        try b.ingestSyncRevisions(Array(try XCTUnwrap(a.syncJournal).revisions.values))
        XCTAssertEqual(a.notes,b.notes)
        XCTAssertEqual(a.notes[0].title,"iPhone")
        XCTAssertTrue(try XCTUnwrap(b.syncJournal).conflictKeys.isEmpty)
    }
    func testInboxAndDeletionAcrossDevices() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let inbox = root.appendingPathComponent("inbox")
        try FileManager.default.createDirectory(at:inbox,withIntermediateDirectories:true)
        let id = UUID()
        let file = inbox.appendingPathComponent(id.uuidString+".json")
        try Data(#"{"version":1,"title":"Capture","sourceURL":"https://example.test","mode":"page","html":"<b>Hi</b>","text":"Hi"}"#.utf8).write(to:file)
        var a = NoteLibrary(); try a.initializeSyncJournal()
        let url = root.appendingPathComponent("notes.json")
        XCTAssertEqual(try CaptureInbox.drain(directory:inbox,libraryURL:url,library:&a).imported,[id])
        var b = NoteLibrary(); try b.initializeSyncJournal()
        try b.ingestSyncRevisions(Array(try XCTUnwrap(a.syncJournal).revisions.values))
        XCTAssertEqual(b.notes,a.notes)
        let old = b; b.delete([id]); try b.recordLocalChanges(from:old)
        try a.ingestSyncRevisions(Array(try XCTUnwrap(b.syncJournal).revisions.values))
        XCTAssertTrue(a.notes.isEmpty)
        try a.ingestSyncRevisions(Array(try XCTUnwrap(old.syncJournal).revisions.values))
        XCTAssertTrue(a.notes.isEmpty)
    }
    func testCorruptIncomingPreservesLibrary() throws {
        var a = NoteLibrary(); try a.initializeSyncJournal()
        let before = a
        let bad = SyncRevision(key:.note(UUID()),parents:[UUID()],value:.deleted)
        XCTAssertThrowsError(try a.ingestSyncRevisions([bad]))
        XCTAssertEqual(a,before)
    }
}
