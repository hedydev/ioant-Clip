#!/usr/bin/env python3
import importlib.util
import io
import json
import pathlib
import plistlib
import struct
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
host = load("host", ROOT / "NativeMessaging/host.py")
installer = load("installer", ROOT / "scripts/install_native_host.py")

class NativeHostTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.inbox = self.root / "inbox"
        self.origin = "chrome-extension://" + installer.extension_id() + "/"
        self.config = {"allowed_origins": [self.origin], "app_path": "/not/executed"}
        self.capture = {"version":1,"title":"测试","sourceURL":"https://example.com","mode":"page","html":"<b>样式</b>","text":"样式"}
    def run_message(self, value=None, origin=None, frame=None, launch=lambda path: True):
        if frame is None:
            body = json.dumps(value).encode()
            frame = struct.pack("=I", len(body)) + body
        result = io.BytesIO()
        host.serve(io.BytesIO(frame), result, origin or self.origin, self.config, self.inbox, launch)
        data = result.getvalue()
        self.assertEqual(struct.unpack("=I", data[:4])[0], len(data)-4)
        return json.loads(data[4:])
    def test_framed_capture(self):
        result = self.run_message({"version":1,"action":"capture","capture":self.capture})
        self.assertTrue(result["ok"]); self.assertTrue(result["opened"])
        path = self.inbox / (result["id"] + ".json")
        self.assertEqual(json.loads(path.read_text()), self.capture)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
    def test_wrong_origin_and_action(self):
        msg = {"version":1,"action":"capture","capture":self.capture}
        self.assertFalse(self.run_message(msg, origin="chrome-extension://unknown/")["ok"])
        self.assertFalse(self.run_message({"version":1,"action":"execute"})["ok"])
        self.assertFalse(self.inbox.exists())
    def test_bad_framing(self):
        for frame in (b"", struct.pack("=I",host.MAX_MESSAGE+1), struct.pack("=I",5)+b"{}"):
            self.assertFalse(self.run_message(frame=frame)["ok"])
    def test_failed_launch_keeps_capture(self):
        result = self.run_message({"version":1,"action":"capture","capture":self.capture},launch=lambda path: False)
        self.assertTrue(result["ok"]); self.assertFalse(result["opened"])
        self.assertEqual(len(list(self.inbox.glob("*.json"))),1)
    def test_install_allowlist_and_app(self):
        app = self.root / "Note.app"
        (app / "Contents").mkdir(parents=True)
        with (app / "Contents/Info.plist").open("wb") as f:
            plistlib.dump({"CFBundleIdentifier":"com.ioant.note.macos"},f)
        support = self.root / "Support"
        self.assertEqual(installer.install(app,support),installer.extension_id())
        for browser in ("Google/Chrome","Microsoft Edge"):
            manifest=json.loads((support/browser/"NativeMessagingHosts/com.ioant.note.capture.json").read_text())
            self.assertEqual(manifest["allowed_origins"],[self.origin])
            self.assertTrue(pathlib.Path(manifest["path"]).is_file())
        self.assertEqual(len(installer.extension_id()),32)

if __name__ == "__main__":
    unittest.main()
