"""Read the active Clip library, including versions that still store JSON."""
import json
import pathlib
import sqlite3
import sys


def library_bytes(legacy):
    database = legacy.with_suffix(".sqlite3")
    if not database.is_file():
        return legacy.read_bytes()
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as connection:
        connection.execute("BEGIN")
        state = dict(connection.execute("SELECT key, payload FROM library_state"))
        if "initialized" not in state:
            return legacy.read_bytes()
        notes = []
        for identifier, created, title in connection.execute(
            "SELECT id, created, title FROM notes ORDER BY created DESC, id"
        ):
            parts = [json.loads(row[0]) for row in connection.execute(
                "SELECT payload FROM parts WHERE note_id = ? ORDER BY position", (identifier,)
            )]
            tags = [row[0] for row in connection.execute(
                "SELECT name FROM tags WHERE note_id = ? ORDER BY position", (identifier,)
            )]
            notes.append(dict(id=identifier, createdAt=created, title=title, tags=tags, parts=parts))
        revisions = []
        for identifier, payload in connection.execute("SELECT id, payload FROM revisions ORDER BY id"):
            # Swift encodes dictionaries with UUID keys as alternating keys and values.
            revisions.extend([identifier, json.loads(payload)])
        value = {"notes": notes, "syncJournal": {"revisions": revisions}}
        palette = {key: json.loads(payload) for key, payload in connection.execute("SELECT key, payload FROM colors")}
        if palette:
            value["tagPalette"] = palette
        if "enrollment" in state:
            value["syncEnrollment"] = json.loads(state["enrollment"])
        return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


if __name__ == "__main__":
    sys.stdout.buffer.write(library_bytes(pathlib.Path(sys.argv[1])))
