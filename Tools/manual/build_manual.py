#!/usr/bin/env python3
"""Builds BAKE's user manual PDF from BAKE_DOCS/manual (guide) and BAKE_DOCS/wiki/nodes (reference).
Standard library only; renders Markdown with `gh api markdown` and prints with headless Chrome."""
import html as htmllib
import os
import re
import sys

GROUP_ORDER = ["In & Out", "Effects › Filters", "Effects › Distortion", "Effects › Dynamics",
               "Effects › Modulation FX", "Time", "Spectral", "Wavetable", "Modulation", "Routing", "Batch"]


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def slugify(text):
    text = htmllib.unescape(re.sub(r"<[^>]+>", "", text)).lower()
    return re.sub(r"[^a-z0-9]+", "-", text).strip("-")


def read_version(show_build_settings):
    m = re.search(r"^\s*MARKETING_VERSION = (\S+)\s*$", show_build_settings, re.M)
    if not m:
        fail("MARKETING_VERSION not found in the build settings")
    return m.group(1)


def strip_wiki_links(md):
    """Links to other wiki pages don't exist in the PDF: keep their text."""
    return re.sub(r"\[([^\]]+)\]\((?!https?://)[^)]*\.md(?:#[^)]*)?\)", r"\1", md)


def parse_node_page(text):
    m = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
    if not m or not re.search(r'^type:\s*"?node"?\s*$', m.group(1), re.M):
        return None
    body = m.group(2)
    title = re.search(r"^# (.+)$", body, re.M).group(1).strip()
    group_match = re.search(r"^\*\*Add Node:\*\*\s*(.+?)\s*$", body, re.M)
    group = group_match.group(1).strip() if group_match else ""
    body = re.split(r"^## See also\s*$", body, flags=re.M)[0].rstrip() + "\n"
    body = re.sub(r"^## ", "#### ", body, flags=re.M)
    body = re.sub(r"^# ", "### ", body, flags=re.M)
    return {"title": title, "group": group, "slug": "node-" + slugify(title),
            "markdown": strip_wiki_links(body)}


def group_nodes(pages):
    unknown = sorted({p["group"] for p in pages} - set(GROUP_ORDER))
    if unknown:
        fail(f"node group(s) not in the manual's order: {', '.join(unknown)}")
    return [(g, sorted((p for p in pages if p["group"] == g), key=lambda p: p["title"].lower()))
            for g in GROUP_ORDER if any(p["group"] == g for p in pages)]


def add_heading_ids(html, prefix=""):
    def repl(m):
        tag, attrs, inner = m.group(1), m.group(2), m.group(3)
        if "id=" in attrs:
            return m.group(0)
        return f'<{tag}{attrs} id="{prefix}{slugify(inner)}">{inner}</{tag}>'
    return re.sub(r"<(h[1-4])([^>]*)>(.*?)</\1>", repl, html, flags=re.S)


def missing_images(html, images_dir):
    names = re.findall(r'<img[^>]+src="images/([^"]+)"', html)
    return [n for n in names if not os.path.exists(os.path.join(images_dir, n))]


def broken_anchors(html):
    ids = set(re.findall(r'\bid="([^"]+)"', html))
    return [a for a in re.findall(r'href="#([^"]+)"', html) if a not in ids]


def check_marks(md):
    return [s.strip() for s in re.findall(r"<!--\s*check:(.*?)-->", md, re.S)]
