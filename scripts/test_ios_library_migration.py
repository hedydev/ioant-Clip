import pathlib
import tempfile
import unittest
from ios_library_migration import copy_if_absent

class MigrationTests(unittest.TestCase):
    def test_original_retained_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source, dest = root/"old/notes.json", root/"new/notes.json"
            source.parent.mkdir()
            data = b'{"notes":[{"id":"test"}],"syncJournal":null}'
            source.write_bytes(data)
            self.assertIn("copied", copy_if_absent(source,dest))
            self.assertEqual(dest.read_bytes(),data)
            self.assertEqual(source.read_bytes(),data)
            dest.write_bytes(b'{"notes":[]}')
            self.assertIn("destination exists",copy_if_absent(source,dest))
            self.assertEqual(dest.read_bytes(),b'{"notes":[]}')
            self.assertEqual(source.read_bytes(),data)
    def test_absent_and_invalid_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory)
            source,dest=root/"old",root/"new"
            self.assertIn("no legacy",copy_if_absent(source,dest))
            source.write_text("{}")
            with self.assertRaises(RuntimeError):
                copy_if_absent(source,dest)
            self.assertFalse(dest.exists())

if __name__ == "__main__":
    unittest.main()
