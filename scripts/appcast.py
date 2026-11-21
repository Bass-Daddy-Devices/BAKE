#!/usr/bin/env python3
"""Reads and edits BAKE's Sparkle feed (appcast.xml) for scripts/release.sh. Standard library only."""
import argparse
import os
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")


def sparkle(name):
    return f"{{{SPARKLE}}}{name}"


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def load(path):
    return ET.parse(path)


def items(tree):
    return tree.getroot().findall("./channel/item")


def item_for_build(tree, build):
    for item in items(tree):
        if (item.findtext(sparkle("version")) or "").strip() == build:
            return item
    fail(f"no item for build {build}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["count", "has-build", "set-notes", "signature", "check"])
    parser.add_argument("file")
    parser.add_argument("--build")
    parser.add_argument("--version")
    parser.add_argument("--url")
    parser.add_argument("--min-items", type=int, default=1)
    parser.add_argument("--min-system")
    args = parser.parse_args()

    if args.command == "count":
        print(len(items(load(args.file))) if os.path.exists(args.file) else 0)
        return

    tree = load(args.file)

    if args.command == "has-build":
        found = any((i.findtext(sparkle("version")) or "").strip() == args.build for i in items(tree))
        sys.exit(0 if found else 1)

    item = item_for_build(tree, args.build)

    if args.command == "set-notes":
        link = item.find(sparkle("releaseNotesLink"))
        if link is None:
            link = ET.SubElement(item, sparkle("releaseNotesLink"))
        link.text = args.url
        tree.write(args.file, encoding="utf-8", xml_declaration=True)
    elif args.command == "signature":
        enclosure = item.find("enclosure")
        signature = enclosure.get(sparkle("edSignature")) if enclosure is not None else None
        if not signature:
            fail(f"build {args.build} has no edSignature")
        print(signature)
    elif args.command == "check":
        if len(items(tree)) < args.min_items:
            fail(f"the feed has {len(items(tree))} items, expected at least {args.min_items}")
        if (item.findtext(sparkle("shortVersionString")) or "").strip() != args.version:
            fail(f"build {args.build} isn't version {args.version}")
        enclosure = item.find("enclosure")
        if enclosure is None or enclosure.get("url") != args.url:
            fail(f"build {args.build}'s enclosure url isn't {args.url}")
        if not enclosure.get(sparkle("edSignature")):
            fail(f"build {args.build} has no edSignature")
        if args.min_system and (item.findtext(sparkle("minimumSystemVersion")) or "").strip() != args.min_system:
            fail(f"build {args.build}'s minimumSystemVersion isn't {args.min_system}")


if __name__ == "__main__":
    main()
