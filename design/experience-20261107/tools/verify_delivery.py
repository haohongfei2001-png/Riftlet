"""Check a standalone export against its literal source payload, without a browser."""
from argparse import ArgumentParser
import base64
from hashlib import sha256
from html.parser import HTMLParser
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_NAMES = ('samples.js', 'baselines.js', 'settings.js', 'app.js')
STYLE_NAMES = ('app.css', 'settings.css')


def expected_payloads(prototype):
    logo = 'data:image/svg+xml;base64,' + base64.b64encode((prototype / 'assets/riftlet.svg').read_bytes()).decode('ascii')
    script = '\n'.join((prototype / name).read_text(encoding='utf-8') for name in SCRIPT_NAMES)
    # Python str.replace is literal. A JavaScript replacement STRING would
    # interpret $$ / $& / $` / $' in the inserted source and corrupt helpers.
    script = script.replace('src="assets/riftlet.svg"', 'src="' + logo + '"')
    style = '\n'.join((prototype / name).read_text(encoding='utf-8') for name in STYLE_NAMES)
    return script, style, logo


class Payloads(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.scripts, self.styles, self.resources = [], [], []
        self.active = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ('script', 'style'):
            self.active = []
            (self.scripts if tag == 'script' else self.styles).append(self.active)
        for attr in ('src', 'href'):
            if tag in ('script', 'link', 'img') and attrs.get(attr):
                self.resources.append(attrs[attr])

    def handle_data(self, value):
        if self.active is not None:
            self.active.append(value)

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.active = None


def check_javascript(script, node='node'):
    executable = shutil.which(node)
    if not executable:
        raise ValueError('Node.js is required for the export syntax gate; install Node or pass --node.')
    result = subprocess.run([executable, '--check', '-'], input=script, text=True, capture_output=True, timeout=30)
    if result.returncode:
        # Do not print a potentially enormous inlined data URL from the source.
        detail = next((line for line in result.stderr.splitlines() if line.startswith(('SyntaxError:', 'Error:'))), 'parse failed')
        raise ValueError('Standalone JavaScript syntax gate failed: ' + detail)
    return subprocess.check_output([executable, '--version'], text=True).strip()


def validate_html(document, prototype, node='node'):
    script, style, logo = expected_payloads(prototype)
    parsed = Payloads()
    parsed.feed(document)
    if len(parsed.scripts) != 1 or len(parsed.styles) != 1:
        raise ValueError('Standalone export must contain exactly one inline script and one inline stylesheet.')
    embedded_script = ''.join(parsed.scripts[0])
    embedded_style = ''.join(parsed.styles[0])
    if embedded_script != '\n' + script + '\n':
        raise ValueError('Standalone JavaScript is not byte-identical to the canonical concatenated source payload.')
    if embedded_style != '\n' + style + '\n':
        raise ValueError('Standalone CSS is not byte-identical to the canonical concatenated source payload.')
    if any(not value.startswith('data:') for value in parsed.resources):
        raise ValueError('Standalone export retains a non-embedded resource.')
    if logo not in parsed.resources:
        raise ValueError('Standalone export is missing the original embedded brand SVG.')
    node_version = check_javascript(embedded_script, node)
    return {'result': 'PASS', 'sourcePayloadExact': True, 'stylesheetExact': True,
            'scriptSHA256': sha256(script.encode('utf-8')).hexdigest(),
            'styleSHA256': sha256(style.encode('utf-8')).hexdigest(),
            'doubleDollarOccurrences': script.count('$$'), 'node': node_version}


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument('--html', type=Path, default=ROOT / 'exports/Riftlet-Experience-Prototype.html')
    parser.add_argument('--node', default='node')
    args = parser.parse_args()
    import json
    try:
        result = validate_html(args.html.read_text(encoding='utf-8'), ROOT / 'prototype', args.node)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, str(error) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
