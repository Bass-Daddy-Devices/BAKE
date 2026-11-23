#!/usr/bin/env python3
"""Builds BAKE's user manual PDF from BAKE_DOCS/manual (guide) and BAKE_DOCS/wiki/nodes (reference).
Standard library only; renders Markdown with `gh api markdown` and prints with headless Chrome."""
import html as htmllib
import os
import re
import sys

GROUP_ORDER = ["In & Out", "Batch", "Effects › Filters", "Effects › Distortion", "Effects › Dynamics",
               "Effects › Modulation FX", "Spectral", "Time", "Wavetable", "Routing", "Modulation"]


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
    body = re.sub(r"^[ \t]*Controls marked ✓ can be modulated: tick them on Page 2 and a pin appears for each\.[ \t]*\n?", "", body, flags=re.M)
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


def add_node_heading_ids(html, slug):
    """A node page's h3 gets exactly `slug`; its sub-headings are prefixed with it so they stay unique."""
    html = add_heading_ids(html, prefix=slug + "-")
    return re.sub(r'<h3([^>]*) id="[^"]*"', rf'<h3\1 id="{slug}"', html, count=1)


def duplicate_ids(html):
    seen, dupes = set(), []
    for i in re.findall(r'\bid="([^"]+)"', html):
        if i in seen and i not in dupes:
            dupes.append(i)
        seen.add(i)
    return dupes


def missing_images(html, images_dir):
    names = re.findall(r'<img[^>]+src="images/([^"]+)"', html)
    return [n for n in names if not os.path.exists(os.path.join(images_dir, n))]


def broken_anchors(html):
    ids = set(re.findall(r'\bid="([^"]+)"', html))
    return [a for a in re.findall(r'href="#([^"]+)"', html) if a not in ids]


def check_marks(md):
    return [s.strip() for s in re.findall(r"<!--\s*check:(.*?)-->", md, re.S)]

import argparse
import base64
import glob
import subprocess
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DOCS = os.path.join(ROOT, "BAKE_DOCS")
MANUAL = os.path.join(DOCS, "manual")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def render(md):
    out = subprocess.run(["gh", "api", "markdown", "-f", "mode=gfm", "-f", f"text={md}"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        fail(f"gh api markdown failed: {out.stderr.strip()}")
    # GitHub adds a link icon (<a class="anchor">…</a>) to each heading; the PDF doesn't want it.
    html = re.sub(r'<a [^>]*class="anchor"[^>]*>.*?</a>', "", out.stdout, flags=re.S)
    return re.sub(r"</?markdown-accessiblity-table>", "", html)


def project_version():
    out = subprocess.run(["xcodebuild", "-showBuildSettings", "-workspace", os.path.join(ROOT, "BAKE_WORKSPACE.xcworkspace"),
                          "-scheme", "BAKE", "-configuration", "Release",
                          "-clonedSourcePackagesDirPath", os.path.join(ROOT, "build", "packages")],
                         capture_output=True, text=True)
    return read_version(out.stdout)


def cover_icon(work):
    icns = glob.glob("/tmp/bake-dd*/Build/Products/*/BAKE.app/Contents/Resources/Bake.icns")
    if not icns:
        fail("no built BAKE.app found for the cover icon; build the app first (see README)")
    png = os.path.join(work, "icon.png")
    subprocess.run(["sips", "-s", "format", "png", icns[0], "--out", png], capture_output=True, check=True)
    with open(png, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def figures(html, start=1):
    """`<p><img src="images/x.png" alt="Caption"></p>` → a numbered figure with its caption.
    Returns the new HTML and the next figure number, so numbering can continue across chapters."""
    count = start - 1
    def repl(m):
        nonlocal count
        count += 1
        return f'<figure><img src="{m.group(1)}"><figcaption>Figure {count}: {m.group(2)}</figcaption></figure>'
    # GitHub wraps each image in a link to itself: allow it and drop it.
    out = re.sub(r'<p>\s*(?:<a [^>]*>)?\s*<img src="(images/[^"]+)" alt="([^"]*)"[^>]*>\s*(?:</a>)?\s*</p>', repl, html)
    return out, count + 1


def build(args):
    version = project_version()
    title = f"BAKE {version} User Manual"
    chapters = sorted(glob.glob(os.path.join(MANUAL, "guide", "[0-9][0-9]-*.md")))
    if not chapters:
        fail("no chapters in BAKE_DOCS/manual/guide")
    marks, sections, toc, figure_no = [], [], [], 1
    for path in chapters:
        md = open(path).read()
        marks += [f"{os.path.basename(path)}: {m}" for m in check_marks(md)]
        html = add_heading_ids(render(md))
        h1 = re.search(r'<h1[^>]*id="([^"]+)"[^>]*>(.*?)</h1>', html, re.S)
        toc.append((h1.group(1), re.sub(r"<[^>]+>", "", h1.group(2)).strip()))
        html, figure_no = figures(html, figure_no)
        sections.append(f'<section class="chapter">{html}</section>')

    pages = [p for p in (parse_node_page(open(f).read()) for f in glob.glob(os.path.join(DOCS, "wiki", "nodes", "*.md"))) if p]
    ref, ref_toc, index = [], [], []
    for group, nodes in group_nodes(pages):
        gid = "group-" + slugify(group)
        ref_toc.append((gid, group))
        ref.append(f'<h2 id="{gid}">{htmllib.escape(group)}</h2>')
        for p in nodes:
            body = add_node_heading_ids(render(p["markdown"]), p["slug"])
            ref.append(f'<div class="node">{body}</div>')
            index.append((p["title"], p["slug"]))

    with tempfile.TemporaryDirectory() as work:
        icon = cover_icon(work)
        toc_html = "".join(f'<li><a href="#{i}">{htmllib.escape(t)}</a></li>' for i, t in toc)
        ref_html = "".join(f'<li><a href="#{i}">{htmllib.escape(t)}</a></li>' for i, t in ref_toc)
        index_html = "".join(f'<li><a href="#{s}">{htmllib.escape(t)}</a></li>' for t, s in sorted(index, key=lambda x: x[0].lower()))
        document = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><title>{title}</title>
<link rel="stylesheet" href="file://{MANUAL}/style/manual.css"><base href="file://{MANUAL}/">
<style>@page {{ @top-right {{ content: "{title}"; font: 8pt "Inter"; color: #888; }} }} @page cover {{ @top-right {{ content: none; }} }}</style></head><body>
<section class="cover"><img src="{icon}"><h1>BAKE</h1><p>User Manual</p><p>Version {version}</p></section>
<section class="part"><h1 id="contents">Contents</h1><nav class="toc"><ol>
<li><a href="#part-guide">Part 1: Guide</a><ol>{toc_html}</ol></li>
<li><a href="#part-nodes">Part 2: Node reference</a><ol>{ref_html}</ol></li>
<li><a href="#node-index">Node index</a></li></ol></nav></section>
<section class="part"><h1 id="part-guide">Part 1: Guide</h1></section>
{''.join(sections)}
<section class="part"><h1 id="part-nodes">Part 2: Node reference</h1>
<p>Every node, grouped as in the Add Node menu. Controls marked ✓ can be modulated: tick them on Page 2 and a pin appears for each.</p>
{''.join(ref)}</section>
<section class="part"><h1 id="node-index">Node index</h1><ul class="index">{index_html}</ul></section>
</body></html>"""

        problems = [f"missing image: {n}" for n in missing_images(document, os.path.join(MANUAL, "images"))]
        problems += [f"broken link: #{a}" for a in broken_anchors(document)]
        problems += [f"duplicate id: {i}" for i in duplicate_ids(document)]
        if problems:
            fail("the manual has problems:\n  " + "\n  ".join(problems))
        for m in marks:
            print(f"check: {m}")

        out_dir = os.path.join(MANUAL, "out")
        os.makedirs(out_dir, exist_ok=True)
        html_path = os.path.join(out_dir, f"BAKE Manual {version}.html")
        open(html_path, "w").write(document)
        if args.html_only:
            print(html_path)
            return
        pdf_path = os.path.join(out_dir, f"BAKE Manual {version}.pdf")
        subprocess.run([CHROME, "--headless", "--no-pdf-header-footer", "--generate-pdf-document-outline",
                        "--allow-file-access-from-files", f"--print-to-pdf={pdf_path}", "file://" + html_path],
                       capture_output=True, check=True)
        print(f"{pdf_path} ({os.path.getsize(pdf_path) // 1024} KB, {len(marks)} check marks)")
        if not args.no_open:
            subprocess.run(["open", pdf_path])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-open", action="store_true")
    parser.add_argument("--html-only", action="store_true")
    build(parser.parse_args())


if __name__ == "__main__":
    main()
