import Foundation

/// Pure projection; NoteLibrary remains the sole owner of its persisted fields.
enum LibrarySyncProjection {
    static func project(notes: [Note], colors: [String: TagColor], journal: SyncJournal) -> (notes: [Note], colors: [String: TagColor]) {
        var byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var palette = colors
        for key in journal.keys {
            let heads = journal.heads(for: key)
            guard let first = heads.first else { continue }
            let conflict = heads.dropFirst().contains { $0.value != first.value }
            switch key {
            case .note(let id):
                if conflict {
                    if let current = byID[id], heads.contains(where: { $0.value == .note(current) }) { continue }
                    if let visible = heads.compactMap({ revision -> Note? in
                        if case .note(let note) = revision.value { return note }; return nil
                    }).first { byID[id] = visible }
                } else {
                    if case .note(let note) = first.value { byID[id] = note }
                    else if first.value == .deleted { byID.removeValue(forKey: id) }
                }
            case .tagColor(let name):
                if conflict {
                    if let current = palette[name], heads.contains(where: { $0.value == .tagColor(current) }) { continue }
                    if let visible = heads.compactMap({ revision -> TagColor? in
                        if case .tagColor(let color) = revision.value { return color }; return nil
                    }).first { palette[name] = visible }
                } else {
                    if case .tagColor(let color) = first.value { palette[name] = color }
                    else if first.value == .deleted { palette.removeValue(forKey: name) }
                }
            }
        }
        let ordered = byID.values.sorted { a, b in
            a.createdAt == b.createdAt ? a.id.uuidString < b.id.uuidString : a.createdAt > b.createdAt
        }
        return (ordered, palette)
    }
}
