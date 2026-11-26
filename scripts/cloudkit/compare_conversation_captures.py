"""Compare recent captures of the same ChatGPT conversation without exporting content."""
import collections
from html.parser import HTMLParser
import json
import pathlib
import sqlite3
import subprocess
from urllib.parse import urlsplit


class MarkupStats(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.counts = collections.Counter()
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        style = (attrs.get("style") or "").replace(" ", "")
        if "data-ioant-layout" in attrs:
            self.counts["fixed_layout"] += 1
        if "content-visibility:auto" in style:
            self.counts["auto_visibility"] += 1
        if "overflow-y:auto" in style or "overflow-y:scroll" in style:
            self.counts["vertical_scroll_boxes"] += 1
        if tag in ("h1", "h2", "h3", "table"):
            self.counts[tag] += 1
        if tag == "img":
            src = attrs.get("src") or attrs.get("data-ioant-image-origin") or ""
            mime = "svg" if src.lower().startswith("data:image/svg+xml") or urlsplit(src).path.endswith(".svg") else "image"
            if src:
                self.counts[mime] += 1
                if src.startswith("data:"):
                    self.counts["embedded_" + mime] += 1
        media = attrs.get("data-ioant-media", tag)
        if media in ("video", "audio"):
            self.counts[media] += 1


def read(path, source=None):
    with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as conn:
        conn.execute("BEGIN")
        count = conn.execute("SELECT COUNT(*) FROM notes").fetchone()[0]
        enrollment = conn.execute("SELECT payload FROM library_state WHERE key = 'enrollment'").fetchone()
        backup = json.loads(enrollment[0]) if enrollment else {}
        if source is None:
            row = conn.execute(
                "SELECT source FROM notes WHERE source LIKE 'https://chatgpt.com/%' "
                "GROUP BY source HAVING count(*) > 1 ORDER BY max(created) DESC LIMIT 1"
            ).fetchone()
            if row is None:
                return count, backup, None, []
            source = row[0]
        notes = []
        for identifier, created in conn.execute(
            "SELECT id, created FROM notes WHERE source = ? ORDER BY created DESC, id LIMIT 8", (source,)
        ):
            parts = [
                json.loads(row[0])
                for row in conn.execute("SELECT payload FROM parts WHERE note_id = ? ORDER BY position", (identifier,))
            ]
            notes.append((identifier, created, parts))
        return count, backup, source, notes


def describe(parts):
    result = []
    for part in parts:
        html = part.get("html") or ""
        result.append(dict(mode=part.get("captureMode") or "unspecified",
                           text_chars=len(part.get("text", "")), html_bytes=len(html.encode()),
                           markup=dict(MarkupStats(html).counts)))
    return result


lib = pathlib.Path("Library/Application Support/ioant-Note/notes.sqlite3")
mac_count, mac_binding, source, mac_notes = read(pathlib.Path.home() / lib)
print("Mac:", mac_count, "notes; bound:", bool(mac_binding), "paused:", mac_binding.get("isPaused", False), flush=True)
if not source:
    raise SystemExit("No repeated ChatGPT conversation found in the current Mac database.")
device = "614FDA13-6198-452B-A6B2-94AA5591B30A"
data = subprocess.check_output(
    ["/usr/bin/xcrun", "simctl", "get_app_container", device, "com.ioant.clip.ios", "data"], text=True, timeout=20
).strip()
ios_count, ios_binding, _, ios_notes = read(pathlib.Path(data) / lib, source)
print("Simulator:", ios_count, "notes; same account:", bool(mac_binding) and mac_binding.get("account") == ios_binding.get("account"), flush=True)
ios_by_id = {identifier: parts for identifier, _, parts in ios_notes}
for number, (identifier, _, parts) in enumerate(mac_notes, 1):
    other = ios_by_id.get(identifier)
    print(json.dumps(dict(mac_newest_first=number, on_simulator=other is not None,
                          same_saved_parts=other == parts, parts=describe(parts)), sort_keys=True), flush=True)
