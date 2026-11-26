"""Report only media/rendering metadata from recent TikTok clips."""
import json
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit
from collections import Counter

class CaptureMarkup(HTMLParser):
    def __init__(self):
        super().__init__()
        self.counts = Counter()
        self.image_kinds = Counter()
        self.preview_tags = []
        self.tag_stack = []

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        preview = 'data-ioant-video-preview' in attrs
        in_preview = preview or any(active for _, active in self.tag_stack)
        if tag not in {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}:
            self.tag_stack.append((tag, in_preview))
        if preview:
            self.counts['preview_boxes'] += 1
            if len(self.preview_tags) < 8:
                styles = {}
                for rule in (attrs.get('style') or '').split(';'):
                    key, colon, value = rule.partition(':')
                    if colon and key.strip() in {'display','position','width','height','visibility','opacity'}:
                        styles[key.strip()] = value.strip()
                self.preview_tags.append(styles)
        if tag == 'img':
            source = (attrs.get('src') or '').partition(',')[0].lower()
            family = source[5:].partition(';')[0] if source.startswith('data:image/') else 'other' if source else 'missing'
            self.image_kinds[(str(in_preview), family)] += 1
        if attrs.get('data-ioant-media') == 'video':
            self.counts['video_entries'] += 1
            if attrs.get('data-ioant-media-src'):
                self.counts['video_sources'] += 1
            if attrs.get('data-ioant-media-file'):
                self.counts['video_files'] += 1
            if attrs.get('data-ioant-media-poster'):
                self.counts['media_posters'] += 1

    def handle_endtag(self, tag):
        for i in range(len(self.tag_stack) - 1, -1, -1):
            if self.tag_stack[i][0] == tag:
                del self.tag_stack[i:]
                break

library = Path.home() / 'Library/Application Support/ioant-Note/notes.json'
notes = sorted(json.loads(library.read_bytes())['notes'], key=lambda note: note['createdAt'], reverse=True)
count = 0
for note in notes:
    for part in note['parts']:
        url = urlsplit(part.get('sourceURL') or '')
        if url.hostname not in {'www.tiktok.com', 'tiktok.com', 'm.tiktok.com'}:
            continue
        if part.get('captureMode') != 'page':
            continue
        html = part.get('html') or ''
        parser = CaptureMarkup()
        parser.feed(html)
        kind = 'explore' if url.path.startswith('/explore') else 'video' if '/video/' in url.path else 'other'
        print('TikTok', kind, 'created', note['createdAt'], 'markup size', len(html), 'counts', dict(parser.counts))
        print('image counts by inside video preview and kind', [(a, b, n) for (a,b),n in parser.image_kinds.items()])
        print('preview box styles', parser.preview_tags, flush=True)
        count += 1
        if count == 3:
            break
    if count == 3:
        break
print('matching recent page captures inspected', count, flush=True)
