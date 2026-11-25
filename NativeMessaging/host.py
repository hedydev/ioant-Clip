#!/usr/bin/python3
"""One-shot Chromium native messaging host; never accepts commands or paths."""
import json
import os
import pathlib
import stat
import struct
import subprocess
import sys
import tempfile
import uuid

MAX_CAPTURE = 32 * 1024 * 1024
MAX_MESSAGE = MAX_CAPTURE + 1024

def read_exact(stream, size):
    result = bytearray()
    while len(result) < size:
        part = stream.read(size - len(result))
        if not part:
            raise ValueError("Incomplete message.")
        result.extend(part)
    return bytes(result)

def receive(stream):
    length, = struct.unpack("=I", read_exact(stream, 4))
    if not 0 < length <= MAX_MESSAGE:
        raise ValueError("Message exceeds supported size.")
    return json.loads(read_exact(stream, length))

def reply(stream, value):
    payload = json.dumps(value, ensure_ascii=True).encode("utf-8")
    stream.write(struct.pack("=I", len(payload)))
    stream.write(payload)
    stream.flush()

def queue(message, inbox):
    if not isinstance(message, dict) or message.get("version") != 1 or message.get("action") != "capture":
        raise ValueError("Unsupported request.")
    capture = message.get("capture")
    if not isinstance(capture, dict) or type(capture.get("version")) is not int or capture["version"] != 1 or capture.get("mode") not in ("page", "selection", "answer", "viewport"):
        raise ValueError("Unsupported capture.")
    for field in ("title", "sourceURL", "html", "text"):
        if not isinstance(capture.get(field), str):
            raise ValueError("Invalid capture field.")
    if not capture["html"].strip() and not capture["text"].strip():
        raise ValueError("Empty capture.")
    if "truncated" in capture and capture["truncated"] is not None and type(capture["truncated"]) is not bool:
        raise ValueError("Invalid truncation flag.")
    data = json.dumps(capture, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(data) > MAX_CAPTURE:
        raise ValueError("Capture exceeds 32 MiB.")
    inbox.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = inbox.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise ValueError("Unsafe capture directory permissions.")
    capture_id = str(uuid.uuid4())
    target = inbox / (capture_id + ".json")
    fd, temp = tempfile.mkstemp(prefix=".incoming-", dir=inbox)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return capture_id

def serve(input_stream, output_stream, origin, config, inbox, launch):
    try:
        if origin not in config["allowed_origins"]:
            raise ValueError("Extension origin is not authorized.")
        capture_id = queue(receive(input_stream), inbox)
        try:
            opened = launch(config["app_path"])
        except Exception:
            opened = False
        reply(output_stream, {"ok": True, "state": "queued", "id": capture_id, "opened": bool(opened)})
    except (ValueError, UnicodeError, KeyError, TypeError):
        reply(output_stream, {"ok": False, "error": "Invalid or unauthorized capture request."})
    except OSError:
        reply(output_stream, {"ok": False, "error": "Unable to save to the local capture inbox."})

def launch(path):
    return subprocess.run(["/usr/bin/open", "-g", "-a", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=8).returncode == 0

def main():
    os.umask(0o077)
    config = json.loads(pathlib.Path(__file__).with_name("config.json").read_text())
    # Single compatible daily inbox shared by the current and legacy host aliases.
    inbox = pathlib.Path.home() / "Library/Application Support/ioant-Note/CaptureInbox"
    serve(sys.stdin.buffer, sys.stdout.buffer, sys.argv[1] if len(sys.argv) > 1 else "", config, inbox, launch)

if __name__ == "__main__":
    main()
