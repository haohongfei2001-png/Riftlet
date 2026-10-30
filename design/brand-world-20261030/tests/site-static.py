#!/usr/bin/env python3
"""Scoped, dependency-free checks for the Riftlet candidate's two public pages.

Run: python3 tests/site-static.py [--strict-assets] [--json]

Checks source-level structure and local dependencies. This does not claim
browser rendering, computed contrast, screen-reader or native app validation.
The default allows only the specifically recorded, still-being-built review
and OG outputs. --strict-assets turns those pending files into failures.
"""
from __future__ import annotations

import argparse
import json
from html.parser import HTMLParser
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
PAGES = [(SITE / "index.html", "en"), (SITE / "zh/index.html", "zh-CN")]
PENDING_OUTPUTS = {
    ROOT / "index.html", SITE / "review.html", SITE / "qa.html",
    SITE / "assets/og-en.png", SITE / "assets/og-zh.png",
}
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}


class Element:
    def __init__(self, tag, attrs=None):
        self.tag = tag
        self.attrs = dict(attrs or [])
        self.children = []
        self.parts = []

    def text(self):
        return " ".join(p.text() if isinstance(p, Element) else p for p in self.parts).strip()


class Document(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.root = Element("document")
        self.stack = [self.root]
        self.nodes = []
        self.feed(source)
        self.close()

    def handle_starttag(self, tag, attrs):
        node = Element(tag, attrs)
        self.stack[-1].children.append(node)
        self.stack[-1].parts.append(node)
        self.nodes.append(node)
        if tag not in VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                self.stack = self.stack[:i]
                return

    def handle_data(self, data):
        self.stack[-1].parts.append(data)

    def all(self, tag):
        return [node for node in self.nodes if node.tag == tag]


def run(strict_assets=False):
    errors, warnings, checks = [], [], []
    documents = {}
    known_local_files = set()
    contrast = []

    def check(condition, name, detail=""):
        (checks if condition else errors).append(name if not detail else f"{name}: {detail}")

    def display(path):
        try:
            return str(path.relative_to(ROOT))
        except ValueError:
            return str(path)

    def document(path):
        if path not in documents:
            documents[path] = Document(path.read_text(encoding="utf-8"))
        return documents[path]

    def local_ref(source_path, ref, kind):
        if not ref:
            errors.append(f"{display(source_path)}: empty {kind} URL")
            return
        parsed = urlsplit(ref)
        if parsed.scheme or parsed.netloc:
            if kind in {"script", "stylesheet", "image", "font", "manifest"}:
                if parsed.scheme != "data":
                    errors.append(f"{display(source_path)}: external runtime resource {ref}")
            if parsed.scheme in {"javascript", "vbscript"}:
                errors.append(f"{display(source_path)}: executable URL {ref}")
            return
        path_text = unquote(parsed.path)
        if not path_text:
            target = source_path
        elif path_text.startswith("/"):
            target = (SITE / path_text.lstrip("/")).resolve()
        else:
            target = (source_path.parent / path_text).resolve()
        if target.is_dir():
            target = target / "index.html"
        if not target.is_relative_to(ROOT):
            errors.append(f"{display(source_path)}: local resource escapes candidate {ref}")
            return
        if not target.exists():
            message = f"{display(source_path)}: missing {kind} {ref}"
            if not strict_assets and target in PENDING_OUTPUTS:
                warnings.append("Pending known deliverable — " + message)
            else:
                errors.append(message)
            return
        known_local_files.add(target)
        if parsed.fragment and target.suffix.lower() == ".html":
            ids = {n.attrs.get("id") for n in document(target).nodes}
            check(unquote(parsed.fragment) in ids,
                  f"{display(source_path)} → {ref}: anchor target exists")

    for path, locale in PAGES:
        label = display(path)
        if not path.is_file():
            errors.append(f"Missing locale entry point: {label}")
            continue
        doc = document(path)
        ids = [node.attrs["id"] for node in doc.nodes if "id" in node.attrs]
        check(len(ids) == len(set(ids)), f"{label}: IDs are unique")
        check(len(doc.all("html")) == 1 and doc.all("html")[0].attrs.get("lang") == locale,
              f"{label}: document language is {locale}")
        for tag in ["main", "h1", "title"]:
            check(len(doc.all(tag)) == 1, f"{label}: exactly one {tag}")
        if doc.all("title"):
            check(bool(doc.all("title")[0].text()), f"{label}: nonempty page title")
        descriptions = [node for node in doc.all("meta") if node.attrs.get("name") == "description"]
        check(len(descriptions) == 1 and len(descriptions[0].attrs.get("content", "")) >= 30,
              f"{label}: descriptive search metadata")
        robots = [node.attrs.get("content", "") for node in doc.all("meta") if node.attrs.get("name") == "robots"]
        check(any("noindex" in value.lower() for value in robots), f"{label}: candidate is noindex")
        check(any(node.attrs.get("name") == "viewport" and "width=device-width" in node.attrs.get("content", "")
                  for node in doc.all("meta")), f"{label}: responsive viewport")
        check(not doc.all("form"), f"{label}: no submission form")
        check(any("skip" in node.attrs.get("class", "").split() and node.attrs.get("href", "").startswith("#")
                  for node in doc.all("a")), f"{label}: keyboard skip link")
        check(any(node.attrs.get("aria-live") == "polite" for node in doc.nodes), f"{label}: polite status announcements")
        check(not any(attr.startswith("on") for node in doc.nodes for attr in node.attrs),
              f"{label}: no inline event handlers")

        labels = {node.attrs.get("for") for node in doc.all("label")}
        for node in doc.nodes:
            attrs = node.attrs
            identity = attrs.get("id", node.tag)
            for attr in ["aria-labelledby", "aria-describedby", "aria-controls"]:
                if attr in attrs:
                    check(all(ref in ids for ref in attrs[attr].split()), f"{label}: {identity} {attr} resolves")
            if node.tag in {"textarea", "select", "input"} and attrs.get("type") != "hidden":
                check(bool(attrs.get("aria-label") or attrs.get("aria-labelledby") or attrs.get("id") in labels),
                      f"{label}: {identity} has an accessible label")
            if node.tag in {"button", "a", "summary"}:
                check(bool(node.text() or attrs.get("aria-label") or attrs.get("aria-labelledby") or
                           any(child.tag == "img" and child.attrs.get("alt") for child in node.children)),
                      f"{label}: {identity} has an accessible name")
            if node.tag == "button":
                check(attrs.get("type") == "button", f"{label}: {identity} is explicitly a non-submit button")
            if node.tag == "img":
                check("alt" in attrs, f"{label}: image {attrs.get('src')} declares alt")
                check(bool(attrs.get("width") and attrs.get("height")), f"{label}: image {attrs.get('src')} reserves dimensions")
                local_ref(path, attrs.get("src", ""), "image")
            if node.tag == "script":
                check("src" in attrs and not node.text(), f"{label}: scripts are local external files")
                if "src" in attrs:
                    local_ref(path, attrs["src"], "script")
            if node.tag == "a" and "href" in attrs:
                local_ref(path, attrs["href"], "link")
                if attrs.get("target") == "_blank":
                    check("noopener" in attrs.get("rel", "").split(), f"{label}: external tab isolates opener")
            if node.tag == "link" and "href" in attrs:
                rel = attrs.get("rel", "")
                kind = "stylesheet" if "stylesheet" in rel else "manifest" if "manifest" in rel else "image" if "icon" in rel else "link"
                local_ref(path, attrs["href"], kind)
            if node.tag == "meta" and attrs.get("property") in {"og:image", "twitter:image"}:
                local_ref(path, attrs.get("content", ""), "image")
                if not attrs.get("content", "").startswith("https://"):
                    warnings.append(f"{label}: share image is relative; set an absolute production URL when adopting")
        csp = [node.attrs.get("content", "") for node in doc.all("meta")
               if node.attrs.get("http-equiv", "").lower() == "content-security-policy"]
        if not csp:
            warnings.append(f"{label}: no CSP meta; recommended deployment header includes connect-src 'none', object-src 'none', base-uri 'none', form-action 'none'")
        elif not any("connect-src 'none'" in value for value in csp):
            warnings.append(f"{label}: CSP does not explicitly deny outbound connections")

    css_path = SITE / "brand.css"
    if css_path.exists():
        css = css_path.read_text(encoding="utf-8")
        css_without_comments = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
        check("prefers-reduced-motion" in css, "CSS: OS reduced-motion treatment exists")
        check(":focus-visible" in css, "CSS: visible keyboard focus treatment exists")
        check(bool(re.search(r"(?:^|})\s*\[hidden\]\s*\{[^}]*display\s*:\s*none\s*!important", css_without_comments)),
              "CSS: global hidden invariant overrides component display rules")
        check("@media" in css and "max-width" in css, "CSS: narrow-layout rules exist")
        check(not re.search(r"@import\b", css), "CSS: no remote or deferred stylesheet import")
        def declarations(selector):
            found = re.search(r"(?:^|})\s*" + re.escape(selector) + r"\s*\{([^}]+)}", css)
            return dict((key.strip(), value.strip()) for key, value in
                        re.findall(r"([\w-]+)\s*:\s*([^;]+)", found.group(1))) if found else {}

        def colour(value):
            if not value or not re.fullmatch(r"#[\da-fA-F]{6}", value):
                return None
            return [int(value[i:i + 2], 16) / 255 for i in (1, 3, 5)]

        def luminance(rgb):
            linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb]
            return .2126 * linear[0] + .7152 * linear[1] + .0722 * linear[2]

        # These exact, opaque base surfaces can be checked mathematically.
        # No claim is made about every descendant, media rule or theme state.
        root_vars = dict(re.findall(r"(--[\w-]+)\s*:\s*([^;}]+)", css.split("*{", 1)[0]))
        for selector, background_selector in [(".composer-foot", ".composer"),
                                              (".source-caption", ".source-window"),
                                              (".existing-attachment", ".composer"),
                                              (".demo-limits", "body")]:
            foreground_props = declarations(selector)
            background_props = declarations(background_selector)
            fg_value = foreground_props.get("color", "")
            bg_value = background_props.get("background", "")
            for key, value in root_vars.items():
                fg_value = fg_value.replace(f"var({key})", value)
                bg_value = bg_value.replace(f"var({key})", value)
            fg, bg = colour(fg_value), colour(bg_value)
            if fg is not None and bg is not None:
                opacity = float(foreground_props.get("opacity", "1"))
                effective = [a * opacity + b * (1 - opacity) for a, b in zip(fg, bg)]
                hi, lo = sorted([luminance(effective), luminance(bg)], reverse=True)
                ratio = (hi + .05) / (lo + .05)
                contrast.append({"selector": selector, "base_light_ratio": round(ratio, 2)})
                check(ratio >= 4.5, f"CSS: {selector} base normal-text contrast ≥ 4.5:1", f"{ratio:.2f}:1")
        for ref in re.findall(r"url\(\s*['\"]?([^)'\"]+)", css):
            local_ref(css_path, ref, "font" if re.search(r"\.(?:woff2?|ttf|otf)(?:\?|$)", ref) else "image")
        local_fonts = list(SITE.rglob("*.woff")) + list(SITE.rglob("*.woff2")) + list(SITE.rglob("*.ttf")) + list(SITE.rglob("*.otf"))
        if local_fonts:
            license_files = [p for p in SITE.rglob("*") if p.is_file() and re.search(r"license|licence|ofl", p.name, re.I)]
            check(bool(license_files), "Fonts: bundled font files have license evidence")
            warnings.append("Bundled font license text still requires human scope review; filename presence is not legal clearance")
        else:
            check(not re.search(r"@font-face", css), "Fonts: system stacks only; no font files are redistributed")
    else:
        errors.append("Missing site/brand.css")

    forbidden = {
        "network fetch": r"\bfetch\s*\(",
        "XMLHttpRequest": r"\b(?:new\s+)?XMLHttpRequest\b",
        "WebSocket/EventSource": r"\bnew\s+(?:WebSocket|EventSource)\s*\(",
        "beacon upload": r"\.sendBeacon\s*\(",
        "browser storage": r"\b(?:localStorage|sessionStorage|indexedDB)\b|\bdocument\s*\.\s*cookie\b",
        "clipboard access": r"\bnavigator\s*\.\s*clipboard\b|\bClipboardItem\b|execCommand\s*\(\s*['\"](?:copy|cut|paste)",
        "screen/camera access": r"\b(?:getDisplayMedia|getUserMedia)\s*\(",
        "service worker": r"\bserviceWorker\s*\.\s*register\s*\(",
        "dynamic code execution": r"\beval\s*\(|\bnew\s+Function\s*\(",
    }
    for filename in ["demo-engine.js", "website.js"]:
        path = SITE / filename
        if not path.exists():
            errors.append(f"Missing site/{filename}")
            continue
        source = path.read_text(encoding="utf-8")
        source_without_comments = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
        source_without_comments = re.sub(r"^\s*//.*$", "", source_without_comments, flags=re.M)
        for name, pattern in forbidden.items():
            check(not re.search(pattern, source_without_comments), f"{filename}: no {name} API")
        result = subprocess.run(["node", "--check", str(path)], capture_output=True, text=True)
        check(result.returncode == 0, f"{filename}: JavaScript parses", result.stderr.strip())
        for resource in set(re.findall(r"['\"](sample-[^'\"]+\.svg)['\"]", source)):
            local_ref(path, "assets/" + resource, "image")

    manifest_path = SITE / "site.webmanifest"
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text())
            local_ref(manifest_path, manifest.get("start_url", ""), "link")
            for icon in manifest.get("icons", []):
                local_ref(manifest_path, icon.get("src", ""), "image")
            check(bool(manifest.get("name")), "Manifest: valid JSON with a name")
        except (ValueError, TypeError) as exc:
            errors.append(f"Manifest: invalid JSON — {exc}")

    return {
        "scope": [display(p) for p, _ in PAGES],
        "passed_checks": len(checks),
        "checked_local_files": sorted(display(p) for p in known_local_files),
        "selected_base_contrast": contrast,
        "errors": sorted(set(errors)),
        "warnings": sorted(set(warnings)),
        "limitations": [
            "Source inspection does not establish computed contrast, visual overflow or touch-target bounds.",
            "Source/API scanning does not replace a browser network audit or screen-reader testing.",
            "No remote-link HTTP requests, browser automation or native app checks are performed.",
        ],
        "status": "PASS" if not errors else "FAIL",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict-assets", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    result = run(strict_assets=args.strict_assets)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"{result['status']}: {result['passed_checks']} scoped source checks; {len(result['checked_local_files'])} resolved local dependencies")
        for message in result["errors"]:
            print("ERROR:", message)
        for message in result["warnings"]:
            print("NOTE:", message)
        for message in result["limitations"]:
            print("LIMIT:", message)
    sys.exit(0 if result["status"] == "PASS" else 1)
