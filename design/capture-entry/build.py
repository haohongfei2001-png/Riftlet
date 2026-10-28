#!/usr/bin/env python3
"""Build the offline design reference; no packages, downloads, or App resources."""

from pathlib import Path
import argparse


ROOT = Path(__file__).resolve().parent
TARGET = ROOT / "Riftlet-Capture-Entry.html"


def render() -> str:
    source = (ROOT / "source.html").read_text(encoding="utf-8")
    notices = (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
    return """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light dark">
  <meta name="description" content="Synthetic offline interaction reference for Riftlet's native capture entry. No OS capture or upload.">
  <title>Riftlet · Capture Entry Reference</title>
  <style>
    :root { color-scheme:light dark; }
    body { margin:0; padding:16px; background:light-dark(#fff,#15171b); }
  </style>
</head>
<body>
<!--
""" + notices.replace("-->", "--&gt;") + "\n-->\n" + source + "\n</body>\n</html>\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the committed standalone is stale.")
    args = parser.parse_args()
    document = render()
    if args.check:
        if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != document:
            raise SystemExit("Standalone is stale; run python3 design/capture-entry/build.py")
        print("Capture-entry standalone matches source.html and third-party notices.")
    else:
        TARGET.write_text(document, encoding="utf-8")
        print(f"Built {TARGET.name} ({TARGET.stat().st_size} bytes; fully offline)")


if __name__ == "__main__":
    main()
