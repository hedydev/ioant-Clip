import unittest
from check_development_identity import identity_hashes, matches_team

class IdentityTest(unittest.TestCase):
    def test_development_only(self):
        a = "A" * 40
        b = "B" * 40
        c = "C" * 40
        self.assertEqual(identity_hashes(f'  1) {a} "Apple Development: Test (FAKE)"\n  2) {b} "Developer ID Application: Test"\n  3) {c} "Apple Distribution: Test"\n'), {a})
    def test_exact_team(self):
        self.assertTrue(matches_team("subject=CN=Apple Development: Test,OU=TESTTEAM01,O=Test,C=US", "TESTTEAM01"))
        self.assertFalse(matches_team("subject=CN=Apple Development: Test,OU=OTHERTEAM1,O=TESTTEAM01", "TESTTEAM01"))
        self.assertFalse(matches_team("subject=CN=TESTTEAM01,OU=TESTTEAM012", "TESTTEAM01"))

if __name__ == "__main__":
    unittest.main()
