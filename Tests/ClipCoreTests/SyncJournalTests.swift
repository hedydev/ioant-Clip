import XCTest
@testable import ClipCore

final class SyncJournalTests: XCTestCase {
    func testOfflineConcurrentEditsAndExplicitResolution() throws {
        let note = Note(title: "original", parts: [.init(html: "<b>Hi</b>", text: "Hi")])
        let key = SyncKey.note(note.id)
        var a = try SyncJournal.bootstrap(NoteLibrary(notes: [note]))
        var b = a
        var left = note; left.title = "Mac"
        var right = note; right.title = "iPhone"
        try a.record(.note(left), for: key)
        try b.record(.note(right), for: key)
        try a.ingest(Array(b.revisions.values))
        try b.ingest(Array(a.revisions.values))
        XCTAssertEqual(a,b)
        XCTAssertEqual(a.heads(for:key).count,2)
        XCTAssertTrue(a.conflictKeys.contains(key))
        XCTAssertThrowsError(try a.record(.note(left), for:key))
        try a.resolve(.note(right), for:key)
        try b.ingest(Array(a.revisions.values))
        XCTAssertTrue(b.conflictKeys.isEmpty)
        XCTAssertEqual(b.heads(for:key).first?.value,.note(right))
    }
    func testDeletionDoesNotResurrectOnStaleDevice() throws {
        let note = Note(title: "note", parts: [.init(text: "content")])
        let key = SyncKey.note(note.id)
        var a = try SyncJournal.bootstrap(NoteLibrary(notes: [note]))
        let stale = a
        try a.record(.deleted, for: key)
        try a.ingest(Array(stale.revisions.values))
        XCTAssertEqual(a.heads(for:key).map(\.value),[.deleted])
        var b = stale
        var edited = note; edited.title = "offline edit"
        try b.record(.note(edited),for:key)
        try a.ingest(Array(b.revisions.values))
        XCTAssertTrue(a.conflictKeys.contains(key))
        XCTAssertEqual(a.heads(for:key).count,2)
    }
    func testRejectsCorruptBatchAtomically() throws {
        let key = SyncKey.note(UUID())
        var a = SyncJournal()
        let bad = SyncRevision(key:key,parents:[UUID()],value:.deleted)
        XCTAssertThrowsError(try a.ingest([bad]))
        XCTAssertTrue(a.revisions.isEmpty)
        let id = UUID()
        let cycle = SyncRevision(id:id,key:key,parents:[id],value:.deleted)
        XCTAssertThrowsError(try a.ingest([cycle]))
        XCTAssertTrue(a.revisions.isEmpty)
    }
    func testBootstrapAssetsAndColorsAndPersistence() throws {
        let note = Note(title:"picture",tags:["Work"],parts:[.init(html:"<svg></svg>",text:"image",image:Data([1,2,3]),imageMIME:"image/png")])
        var library = NoteLibrary(notes:[note]); library.setColor(.purple,for:"work")
        let journal = try SyncJournal.bootstrap(library)
        XCTAssertEqual(journal.heads(for:.note(note.id)).first?.value,.note(note))
        XCTAssertEqual(journal.heads(for:.tagColor("work")).first?.value,.tagColor(.purple))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("journal.json")
        try journal.save(to:url)
        XCTAssertEqual(try SyncJournal.load(from:url),journal)
        XCTAssertTrue(try SyncJournal.bootstrap(NoteLibrary()).revisions.isEmpty)
    }
}
