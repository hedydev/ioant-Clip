import XCTest
@testable import ClipCore

final class SQLiteNoteRepositoryTests: XCTestCase {
    func testLegacyMigrationAndKeysetPagination() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.json")
        let sameTime = Date(timeIntervalSinceReferenceDate: 100)
        let notes = (0..<1000).map { index in
            Note(title: "Clip \(index)", createdAt: sameTime, tags: index.isMultiple(of: 2) ? ["Journal"] : [],
                 parts: [NotePart(html: "<p>Full body</p>", text: "Details \(index)", sourceURL: "https://example.com/")])
        }
        var legacy = NoteLibrary(notes: notes)
        legacy.setColor(.blue, for: "Journal")
        try legacy.enrollSync(account: SyncAccount(provider: "icloud", namespace: "test", accountID: "example"),
                              replaceLocalHistory: true)
        try legacy.save(to: url)
        let original = try Data(contentsOf: url)

        let database = try SQLiteNoteRepository(legacyURL: url)
        XCTAssertEqual(try database.enrollment, legacy.syncEnrollment)
        XCTAssertEqual(try database.colors(), legacy.syncColors)
        XCTAssertEqual(try database.tagCounts()["Journal"], 500)
        XCTAssertEqual(try database.count(filter: .untagged), 500)
        XCTAssertEqual(try database.count(query: "details 999"), 1)
        XCTAssertEqual(try database.note(notes[999].id), notes[999])
        XCTAssertEqual(try SQLiteNoteRepository.readNote(notes[999].id, legacyURL: url), notes[999])
        XCTAssertEqual(try database.snapshot().syncJournal, legacy.syncJournal)

        var cursor: SQLiteNoteRepository.Row?
        var visited: [UUID] = []
        while true {
            let page = try database.page(query: "", filter: .all, after: cursor, limit: 40)
            guard let last = page.last else { break }
            XCTAssertLessThanOrEqual(page.count, 40)
            visited += page.map(\.id)
            cursor = last
        }
        XCTAssertEqual(visited, notes.map(\.id).sorted { $0.uuidString < $1.uuidString })

        let previous = try database.snapshot()
        var edited = previous
        edited.delete([notes[999].id])
        try edited.recordLocalChanges(from: previous)
        try database.save(edited, previous: previous)
        XCTAssertNil(try SQLiteNoteRepository.readNote(notes[999].id, legacyURL: url))
        XCTAssertEqual(try SQLiteNoteRepository(legacyURL: url).count(), 999)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testStorageUsageSeparatesEmbeddedMediaFromDocuments() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.json")
        let svg = "<svg><path /></svg>"
        let html = """
            <p>正文</p><img src="https://example.test/external.png">
            <img src="data:image/png;base64,AQID">
            <span style="background:url(data:image/png;base64,AQI=)"></span>
            <video src="data:video/mp4;base64,AQIDBA=="></video>
            <audio src="data:audio/mpeg;base64,AQ=="></audio>
            \(svg)<img src="data:image/svg+xml,%3Csvg%2F%3E">
            """
        let document = """
            <p>正文</p><img src="https://example.test/external.png">
            <img src="">
            <span style="background:url()"></span>
            <video src=""></video>
            <audio src=""></audio>
            <img src="">
            """
        let note = Note(title: "Media", parts: [NotePart(html: html, text: "文字", image: Data([0, 1]))])
        let library = NoteLibrary(notes: [note])
        try library.save(to: url)
        let database = try SQLiteNoteRepository(legacyURL: url)
        let usage = try SQLiteNoteRepository.readStorageContentUsage(legacyURL: url)
        XCTAssertEqual(usage.documentBytes, Int64(document.utf8.count + "文字".utf8.count))
        XCTAssertEqual(usage.imageBytes, 7)
        XCTAssertEqual(usage.svgBytes, Int64(svg.utf8.count + "<svg/>".utf8.count))
        XCTAssertEqual(usage.videoBytes, 4)
        XCTAssertEqual(usage.audioBytes, 1)
        XCTAssertEqual(try database.note(note.id), note)
    }
}
