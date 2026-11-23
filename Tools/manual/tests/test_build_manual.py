import os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import build_manual as bm

PAGE = """---
title: "Half Time"
type: "node"
---
# Half Time

Slows the sound. See [length rules](../concepts/length-rules.md).

**Add Node:** Time
**Inputs:** In (audio, required)

## On the card

| Control | Range |
|---|---|
| Speed | 0.001 to 1 × |

## See also

- [All nodes](index.md)
"""

class Tests(unittest.TestCase):
    def test_read_version(self):
        text = "Build settings for action build and target BAKE:\n    MARKETING_VERSION = 1.0.0\n    PRODUCT_NAME = BAKE\n"
        self.assertEqual(bm.read_version(text), "1.0.0")

    def test_parse_node_page(self):
        page = bm.parse_node_page(PAGE)
        self.assertEqual(page["title"], "Half Time")
        self.assertEqual(page["group"], "Time")
        self.assertEqual(page["slug"], "node-half-time")
        self.assertNotIn("See also", page["markdown"])
        self.assertNotIn("title:", page["markdown"])
        self.assertIn("### Half Time", page["markdown"])
        self.assertIn("#### On the card", page["markdown"])

    def test_non_node_page_is_skipped(self):
        self.assertIsNone(bm.parse_node_page("---\ntitle: x\ntype: concept\n---\n# x\n"))

    def test_group_order_and_alphabetical(self):
        pages = [{"title": "Reverb", "group": "Time"}, {"title": "Delay", "group": "Time"},
                 {"title": "Audio", "group": "In & Out"}]
        grouped = bm.group_nodes(pages)
        self.assertEqual([g for g, _ in grouped], ["In & Out", "Time"])
        self.assertEqual([p["title"] for p in grouped[1][1]], ["Delay", "Reverb"])

    def test_group_order_matches_add_node_menu(self):
        pages = [{"title": t, "group": g} for t, g in
                 [("a", "Modulation"), ("b", "Routing"), ("c", "Time"), ("d", "Effects › Spectral"), ("e", "Batch"), ("f", "In & Out")]]
        self.assertEqual([g for g, _ in bm.group_nodes(pages)],
                         ["In & Out", "Batch", "Effects › Spectral", "Time", "Routing", "Modulation"])

    def test_spectral_is_nested_under_effects(self):
        page = bm.parse_node_page("---\ntype: node\n---\n# Vocoder\n\n**Add Node:** Spectral\n\nText.\n")
        self.assertEqual(page["group"], "Effects › Spectral")
        self.assertIn("**Add Node:** Effects › Spectral", page["markdown"])
        self.assertIn("Effects › Spectral", bm.GROUP_ORDER)
        self.assertNotIn("Spectral", bm.GROUP_ORDER)

    def test_figure_numbers_continue(self):
        one = '<p><img src="images/a.png" alt="A"></p><p><img src="images/b.png" alt="B"></p>'
        html, nxt = bm.figures(one)
        self.assertIn("Figure 1: A", html)
        self.assertIn("Figure 2: B", html)
        html, nxt = bm.figures('<p><img src="images/c.png" alt="C"></p>', nxt)
        self.assertIn("Figure 3: C", html)
        self.assertEqual(nxt, 4)

    def test_unknown_group_fails(self):
        with self.assertRaises(SystemExit):
            bm.group_nodes([{"title": "X", "group": "Nowhere"}])

    def test_strip_wiki_links_keeps_text(self):
        self.assertEqual(bm.strip_wiki_links("See [length rules](../concepts/length-rules.md#a)."),
                         "See length rules.")
        self.assertEqual(bm.strip_wiki_links("[site](https://bake.bass-daddy.com)"),
                         "[site](https://bake.bass-daddy.com)")

    def test_add_heading_ids(self):
        html = bm.add_heading_ids("<h2>Quick start: your first bake</h2>")
        self.assertIn('id="quick-start-your-first-bake"', html)
        self.assertIn('id="node-half-time"', bm.add_heading_ids("<h3>Half Time</h3>", prefix="node-"))

    def test_missing_images(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "a.png"), "wb").close()
            html = '<img src="images/a.png"><img src="images/b.png">'
            self.assertEqual(bm.missing_images(html, d), ["b.png"])

    def test_broken_anchors(self):
        html = '<h2 id="baking">Baking</h2><a href="#baking">x</a><a href="#nope">y</a><a href="https://x">z</a>'
        self.assertEqual(bm.broken_anchors(html), ["nope"])

    def test_duplicate_ids(self):
        html = '<h4 id="a">x</h4><h4 id="a">y</h4><h4 id="a">z</h4><h4 id="b">w</h4>'
        self.assertEqual(bm.duplicate_ids(html), ["a"])
        self.assertEqual(bm.duplicate_ids('<h4 id="a">x</h4><h4 id="b">y</h4>'), [])

    def test_node_ids(self):
        html = bm.add_node_heading_ids("<h3>Half Time</h3><h4>On the card</h4>", "node-half-time")
        self.assertIn('<h3 id="node-half-time">', html)
        self.assertIn('id="node-half-time-on-the-card"', html)

    def test_parse_node_page_drops_modulation_boilerplate(self):
        text = PAGE.replace("## See also", "  Controls marked ✓ can be modulated: tick them on Page 2 and a pin appears for each.  \n\nKept line.\n\n## See also")
        md = bm.parse_node_page(text)["markdown"]
        self.assertNotIn("Controls marked", md)
        self.assertIn("Kept line.", md)

    def test_chapter_ids_are_unique_per_chapter(self):
        a = bm.add_chapter_heading_ids("<h1>Settings</h1><h2>Updates</h2>")
        b = bm.add_chapter_heading_ids("<h1>Welcome</h1><h2>Updates</h2>")
        self.assertIn('<h1 id="settings">', a)
        self.assertIn('<h1 id="welcome">', b)
        self.assertEqual(bm.duplicate_ids(a + b), [])
        self.assertIn('id="settings-updates"', a)

    def test_check_marks(self):
        self.assertEqual(bm.check_marks("a <!-- check: does ⌘K open search? --> b"),
                         ["does ⌘K open search?"])

if __name__ == "__main__":
    unittest.main()
