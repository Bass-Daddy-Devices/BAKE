import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "appcast.py")

FEED = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>BAKE</title>
    <item>
      <title>1.0.0</title>
      <sparkle:version>412</sparkle:version>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/bassDaddyDevices/BAKE/releases/download/v1.0.0/BAKE-1.0.0.dmg"
                 length="3074013" type="application/octet-stream" sparkle:edSignature="c2lnbmF0dXJl"/>
    </item>
  </channel>
</rss>
"""

URL = "https://github.com/bassDaddyDevices/BAKE/releases/download/v1.0.0/BAKE-1.0.0.dmg"


def run(*args):
    return subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.feed = os.path.join(self.dir.name, "appcast.xml")
        with open(self.feed, "w") as f:
            f.write(FEED)

    def tearDown(self):
        self.dir.cleanup()

    def test_count(self):
        self.assertEqual(run("count", self.feed).stdout.strip(), "1")
        self.assertEqual(run("count", os.path.join(self.dir.name, "missing.xml")).stdout.strip(), "0")

    def test_has_build(self):
        self.assertEqual(run("has-build", self.feed, "--build", "412").returncode, 0)
        self.assertEqual(run("has-build", self.feed, "--build", "413").returncode, 1)

    def test_signature(self):
        self.assertEqual(run("signature", self.feed, "--build", "412").stdout.strip(), "c2lnbmF0dXJl")

    def test_set_notes_then_check(self):
        notes = "https://bake.bass-daddy.com/notes/1.0.0.html"
        self.assertEqual(run("set-notes", self.feed, "--build", "412", "--url", notes).returncode, 0)
        with open(self.feed) as f:
            text = f.read()
        self.assertIn(notes, text)
        self.assertIn("xmlns:sparkle=", text)
        result = run("check", self.feed, "--build", "412", "--version", "1.0.0", "--url", URL,
                     "--min-items", "1", "--min-system", "26.0")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_check_fails_on_a_wrong_url(self):
        result = run("check", self.feed, "--build", "412", "--version", "1.0.0", "--url", URL + "x",
                     "--min-items", "1", "--min-system", "26.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("url", result.stderr)

    def test_check_fails_when_old_items_were_dropped(self):
        result = run("check", self.feed, "--build", "412", "--version", "1.0.0", "--url", URL,
                     "--min-items", "2", "--min-system", "26.0")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
