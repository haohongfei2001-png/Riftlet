#!/usr/bin/env python3
"""Serve a loopback preview of the release dialog and consumer pages."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]


def preview_homepage():
    source = (ROOT / "index.html").read_text(encoding="utf-8")
    dialog_marker = '<dialog class="release-dialog" id="release-dialog"'
    before, marker, rest = source.partition(dialog_marker)
    dialog, closing, after = rest.partition("</dialog>")
    start = dialog.find('<a class="button button-primary"')
    end = dialog.find("</a>", start)
    if not marker or not closing or start < 0 or end < 0 or "View project progress" not in dialog[start:end]:
        raise ValueError("The homepage release dialog changed. Review its current action before previewing.")
    links = """
<a class="button button-primary preview-zh" lang="zh-CN" href="download/index.html">查看下载与版本说明</a>
<a class="button button-primary preview-en" lang="en" href="download/en.html">Downloads and version notes</a>
"""
    # Both links use the homepage's existing language selection and button style.
    style = """<style>
#release-dialog .preview-en, html:lang(en) #release-dialog .preview-zh {display:none}
html:lang(en) #release-dialog .preview-en {display:inline-flex}
</style>"""
    # An English consumer page can link back to the same language in this preview.
    restore_language = """<script>
document.addEventListener('DOMContentLoaded', () => {
  if (new URLSearchParams(location.search).get('lang') === 'en' && document.documentElement.lang !== 'en') {
    document.getElementById('language-toggle').click();
  }
});
</script>"""
    return (before.replace("</head>", style + "</head>", 1) + marker
            + dialog[:start] + links + dialog[end + len("</a>"):] + closing
            + after.replace("</body>", restore_language + "</body>", 1))


def stage_preview(destination):
    for name in ("download", "guide", "privacy", "website-assets"):
        shutil.copytree(ROOT / name, destination / name)
    (destination / "website").mkdir()
    for name in ("website/consumer.css", "website-v2.css", "website-v2.js", "favicon.svg", "site.webmanifest"):
        shutil.copyfile(ROOT / name, destination / name)
    (destination / "index.html").write_text(preview_homepage(), encoding="utf-8")


class PreviewHandler(SimpleHTTPRequestHandler):
    def list_directory(self, path):
        self.send_error(404)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=0, help="Local port (default: choose an available port)")
    args = parser.parse_args()
    with TemporaryDirectory(prefix="riftlet-site-preview-") as folder:
        stage_preview(Path(folder))
        handler = partial(PreviewHandler, directory=folder)
        with ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
            print(f"Riftlet preview: http://127.0.0.1:{server.server_port}/", flush=True)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass


if __name__ == "__main__":
    main()
