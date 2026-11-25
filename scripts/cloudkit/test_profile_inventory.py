import datetime
import unittest
from profile_inventory import matching_profile

class ProfileTest(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime.now(datetime.timezone.utc)
    def make(self, platform):
        return {
            "TeamIdentifier":["FAKETEAM"],
            "Platform":["iOS" if platform == "iOS" else "OSX"],
            "ExpirationDate": self.now + datetime.timedelta(days=2),
            "Entitlements":{
                "application-identifier":"FAKETEAM.com.ioant.clip."+("ios" if platform=="iOS" else "macos"),
                "com.apple.developer.team-identifier":"FAKETEAM",
                "get-task-allow":True,
                "com.apple.developer.icloud-container-identifiers":["iCloud.example.review"],
                "com.apple.developer.icloud-services":["CloudKit"],
                "com.apple.developer.icloud-container-environment":["Development","Production"],
            }
        }
    def test_valid(self):
        for platform in ["macOS","iOS"]:
            self.assertEqual(matching_profile(self.make(platform),platform,self.now),("FAKETEAM",{"iCloud.example.review"}))
    def test_wrong_bundle_and_expired(self):
        p=self.make("iOS")
        self.assertIsNone(matching_profile(p,"macOS",self.now))
        p["ExpirationDate"]=self.now
        self.assertIsNone(matching_profile(p,"iOS",self.now))
    def test_production_only_and_wrong_team(self):
        p=self.make("iOS")
        p["Entitlements"]["com.apple.developer.icloud-container-environment"]="Production"
        self.assertIsNone(matching_profile(p,"iOS",self.now))
        p=self.make("iOS")
        p["Entitlements"]["com.apple.developer.team-identifier"]="OTHER"
        self.assertIsNone(matching_profile(p,"iOS",self.now))
    def test_wildcard_container(self):
        p=self.make("macOS")
        p["Entitlements"]["com.apple.developer.icloud-container-identifiers"]=["iCloud.*"]
        self.assertEqual(matching_profile(p,"macOS",self.now),("FAKETEAM",set()))

if __name__ == "__main__":
    unittest.main()
