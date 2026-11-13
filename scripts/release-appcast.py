#!/usr/bin/env python3
"""Prepare a reviewed stable feed. All remote operations are anonymous and read-only."""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
INFO = ROOT / 'Resources/Info.plist'
FEED = 'https://riftlet.com/updates/stable.xml'
REPO = 'haohongfei2001-png/Riftlet'
WEB = 'https://github.com/' + REPO
API = 'https://api.github.com/repos/' + REPO
TEAM = 'ZB9D4T66QB'
ACCOUNT = 'com.riftlet.app.stable'
NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
# Universal CLI binaries from the verified official Sparkle 2.10.1 tarball.
TOOL_SHA = {
    'generate_keys': 'c37679f98d9121981cf7b2d18592fdc8b44931bffa604acf10c9e11791b6222e',
    'sign_update': '43c249771bafc3aa581228abae00731a012d324691b8292860896635050be76b',
    'generate_appcast': 'cdc53c1da293c5f89648929678df2072f72a9f18d91744a06fcb8cc0e12a3219',
}
EMPTY = (b'<?xml version="1.0" encoding="UTF-8"?>\n'
         b'<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
         b'<channel><title>Riftlet</title><link>https://riftlet.com/</link>'
         b'<description>Riftlet stable updates</description></channel></rss>\n')


def check(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(path):
    return json.loads(path.read_bytes())


def sha(path):
    with path.open('rb') as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def git_api(endpoint):
    request = urllib.request.Request(API + endpoint, headers={'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=40) as reply:
        return json.load(reply)


def fetch(url, dest, max_bytes):
    subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error',
                    '--proto', '=https', '--proto-redir', '=https', '--max-time', '180',
                    '--max-filesize', str(max_bytes), '--output', dest, url], check=True)
    check(0 < dest.stat().st_size <= max_bytes, 'download size mismatch')


def tool(directory, name, *args):
    binary = directory / name
    check(sha(binary) == TOOL_SHA[name], f'unexpected {name}; use the official Sparkle 2.10.1 tools')
    return subprocess.check_output([binary, '--account', ACCOUNT, *args], text=True)


def verify(path, signature=None):
    command = ['xcrun', 'swift', str(ROOT / 'scripts/verify-update-signature.swift'), str(INFO), str(path)]
    if signature is not None:
        command.append(signature)
    subprocess.run(command, check=True)


def version(value):
    check(isinstance(value, str) and re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', value),
          'expected a stable three-part marketing version')
    return tuple(map(int, value.split('.')))


def number(value):
    check(isinstance(value, str) and re.fullmatch(r'[1-9][0-9]*', value), 'expected a positive integer build')
    return int(value)


def name_for(v):
    version(v)
    return 'Riftlet-' + v + '.dmg'


def previous_version(feed):
    # Only signed stable feeds produced by this release tool are accepted as predecessors.
    root = ET.parse(feed).getroot()
    check(root.tag == 'rss' and root.get('version') == '2.0' and len(root.findall('channel')) == 1, 'invalid RSS')
    channel = root.find('channel')
    items = channel.findall('item')
    check(len(items) <= 1, 'expected the single universal stable update')
    if not items:
        return (1, 0, 0), 22
    item = items[0]
    return version(item.findtext(NS + 'shortVersionString')), number(item.findtext(NS + 'version'))


def require_successor(previous, v, build):
    old_v, old_b = previous
    check(version(v) > old_v and number(build) > old_b, 'both marketing version and build must increase')


def validate_item(feed, v, build, size, body):
    channel = ET.parse(feed).getroot().find('channel')
    check(channel is not None and channel.findtext('title') == 'Riftlet', 'incorrect feed identity')
    items = channel.findall('item')
    check(len(items) == 1, 'one universal update required')
    item = items[0]
    check(previous_version(feed) == (version(v), number(build)), 'generated version or build mismatch')
    check(item.findtext(NS + 'minimumSystemVersion') == '13.0', 'minimum system mismatch')
    for key in ['deltas', 'channel', 'criticalUpdate', 'informationalUpdate', 'releaseNotesLink',
                'minimumAutoupdateVersion', 'minimumUpdateVersion', 'maximumSystemVersion', 'hardwareRequirements']:
        check(item.find(NS + key) is None, 'unexpected update policy: ' + key)
    notes = item.find('description')
    check(notes is not None and notes.get(NS + 'format') == 'plain-text' and notes.text == body,
          'release notes differ from immutable public release')
    check(item.findtext('link') == 'https://riftlet.com/', 'invalid product URL')
    enclosures = item.findall('enclosure')
    check(len(enclosures) == 1, 'one full download required')
    enclosure = enclosures[0]
    check(enclosure.get('url') == f'{WEB}/releases/download/v{v}/{name_for(v)}'
          and enclosure.get('length') == str(size) and enclosure.get('type') == 'application/octet-stream',
          'download URL, type or length mismatch')
    signature = enclosure.get(NS + 'edSignature', '')
    check(len(base64.b64decode(signature, validate=True)) == 64, 'invalid EdDSA signature')
    return signature


def published_release(v, digest, size):
    tag = 'v' + v
    release = git_api('/releases/tags/' + tag)
    check(release.get('tag_name') == tag and release.get('draft') is False and release.get('prerelease') is False
          and release.get('immutable') is True and release.get('published_at'), 'expected a published immutable stable GitHub Release')
    assets = [a for a in release['assets'] if a['name'] == name_for(v)]
    check(len(assets) == 1, 'missing or ambiguous GitHub asset')
    asset = assets[0]
    link = WEB + '/releases/download/' + tag + '/' + name_for(v)
    check(asset.get('state') == 'uploaded' and asset.get('size') == size and asset.get('digest') == 'sha256:' + digest
          and asset.get('browser_download_url') == link, 'public asset differs from notarized release receipt')
    body = release.get('body', '').replace('\r\n', '\n').strip()
    check(body and len(body) <= 100000, 'missing or oversized public update notes')
    return link, body


def source_matches(source, tag):
    check(re.fullmatch('[0-9a-f]{40}', source), 'invalid source commit')
    target = git_api('/commits/' + tag)['sha']
    check(re.fullmatch('[0-9a-f]{40}', target), 'invalid release tag commit')
    main = git_api('/git/ref/heads/main')['object']['sha']
    relationship = git_api('/compare/' + target + '...' + main)
    check(relationship['merge_base_commit']['sha'] == target and relationship['status'] in ('identical', 'ahead'),
          'release tag is outside the official main history')
    if target != source:
        diff = git_api('/compare/' + source + '...' + target)
        check(diff['merge_base_commit']['sha'] == source
              and [f['filename'] for f in diff['files']] == ['engineering/mainline/source-admission.json'],
              'release tag differs from signed product source')


def verify_transition(old, new):
    verify(new)
    latest = previous_version(new)
    if old is None:
        check(not ET.parse(new).findall('./channel/item'), 'initial feed must contain an empty signed channel')
        return
    if old.read_bytes() == new.read_bytes():
        return
    verify(old)
    previous = previous_version(old)
    check(latest[0] > previous[0] and latest[1] > previous[1],
          'feed replacement must increase both stable version and build')


def verify_github_transition():
    event = read_json(Path(os.environ['GITHUB_EVENT_PATH']))
    kind = os.environ['GITHUB_EVENT_NAME']
    if kind == 'pull_request':
        base = event['pull_request']['base']['sha']
    elif kind == 'push':
        base = event['before']
        if base == '0' * 40:   # First push of a non-main development branch.
            check(event['ref'] != 'refs/heads/main', 'missing main predecessor')
            base = 'HEAD^1'
    else:
        raise ValueError('unsupported CI event: ' + kind)
    check(base == 'HEAD^1' or re.fullmatch('[0-9a-f]{40}', base), 'invalid CI base')
    def git(*args):
        return subprocess.check_output(['git', '-C', ROOT, *args])
    git('merge-base', '--is-ancestor', base, 'HEAD')
    path = 'updates/stable.xml'
    with tempfile.TemporaryDirectory() as folder:
        previous = None
        if git('ls-tree', base, '--', path):
            previous = Path(folder) / 'previous.xml'
            previous.write_bytes(git('show', base + ':' + path))
        verify_transition(previous, ROOT / path)


def atomic_output(path, data):
    # Place fully verified bytes into an unused filename. A racing run cannot replace them.
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent) as staging:
        staging.write(data)
        staging.flush()
        os.fsync(staging.fileno())
        os.chmod(staging.name, 0o644)
        os.link(staging.name, path)


def check_host_policy(info):
    check(info.get('SUFeedURL') == FEED and info.get('SURequireSignedFeed') is True
          and info.get('SUVerifyUpdateBeforeExtraction') is True
          and type(info.get('SUSignedFeedFailureExpirationInterval')) is int
          and info['SUSignedFeedFailureExpirationInterval'] == 0, 'incorrect signed feed policy')


def check_host_key(tools):
    info = plistlib.loads(INFO.read_bytes())
    check_host_policy(info)
    check(tool(tools, 'generate_keys', '-p').strip() == info.get('SUPublicEDKey'),
          'Keychain signatory does not match the compiled public key')


def prepare(args, tmp):
    spec = importlib.util.spec_from_file_location('release_dmg', ROOT / 'scripts/release-dmg.py')
    dmg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dmg)
    workspace = args.workspace.resolve()
    delivered = read_json(workspace / 'website-release.json')
    receipt = read_json(workspace / 'formal-dmg/dmg-receipt.json')
    package = workspace / 'Riftlet-Release'
    manifest = dmg.R.verify_package(package, receipt['manifestSHA256'], TEAM)
    check(manifest['stage'] == 'STAPLED', 'app must be stapled')
    build_info = manifest['build']
    v, b = build_info['version'], build_info['build']
    check(build_info.get('distributionChannel') == 'stable' and build_info.get('bundleIdentifier') == 'com.riftlet.app'
          and set(build_info['architectures']) == {'arm64', 'x86_64'}, 'invalid product identity')
    check(delivered.get('status') == 'VERIFIED_FOR_PUBLICATION_REVIEW' and receipt.get('stage') == 'VERIFIED_STAPLED_DMG'
          and receipt.get('notaryStatus') == 'Accepted' and receipt.get('teamID') == TEAM
          and receipt.get('archive') == name_for(v) and receipt.get('source') == build_info['source']['commit'],
          'release must already be signed, notarized, and verified')
    info = plistlib.loads((package / 'Riftlet.app/Contents/Info.plist').read_bytes())
    source_info = plistlib.loads(INFO.read_bytes())
    check_host_policy(info)
    for key in ['SUPublicEDKey', 'SUFeedURL', 'SURequireSignedFeed', 'SUVerifyUpdateBeforeExtraction',
                'SUSignedFeedFailureExpirationInterval']:
        check(info.get(key) == source_info[key], 'updater setting mismatch: ' + key)
    installed = tmp / 'previous.xml'
    fetch(FEED, installed, 2 * 1024 * 1024)
    check(installed.read_bytes() == (ROOT / 'updates/stable.xml').read_bytes(),
          'website feed and checkout differ; synchronize before generating')
    verify(installed)
    require_successor(previous_version(installed), v, b)
    size, digest = receipt['bytes'], receipt['sha256']
    check(isinstance(size, int) and size > 0 and re.fullmatch('[0-9a-f]{64}', digest), 'invalid artifact receipt')
    url, body = published_release(v, digest, size)
    source_matches(build_info['source']['commit'], 'v' + v)
    archives = tmp / 'archives'
    archives.mkdir()
    archive = archives / name_for(v)
    fetch(url, archive, size)
    check(archive.stat().st_size == size and sha(archive) == digest, 'public download hash mismatch')
    dmg.image_signature(archive, TEAM, tmp)
    dmg.ticket(archive, tmp / 'ticket.log')
    dmg.assess(archive, 'open', tmp)
    dmg.inspect_image(archive, manifest, tmp)
    # Keep Sparkle notes in the signed XML. Plain text avoids loading remote HTML.
    archive.with_suffix('.txt').write_text(body)
    feed = archives / 'stable.xml'
    tool(args.tools, 'generate_appcast', '--download-url-prefix', url.rsplit('/', 1)[0] + '/',
         '--link', 'https://riftlet.com/', '--embed-release-notes', '--maximum-deltas', '0',
         '--versions', b, '-o', str(feed), str(archives))
    tool(args.tools, 'sign_update', '--verify', str(feed))
    verify(feed)
    signature = validate_item(feed, v, b, size, body)
    tool(args.tools, 'sign_update', '--verify', str(archive), signature)
    verify(archive, signature)
    # Re-read before staging to catch a competing approved release.
    current = tmp / 'current.xml'
    fetch(FEED, current, 2 * 1024 * 1024)
    check(current.read_bytes() == installed.read_bytes(), 'live feed changed during generation')
    return feed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest='mode', required=True)
    for name in ['bootstrap', 'prepare']:
        p = modes.add_parser(name)
        p.add_argument('--tools', type=Path, required=True, help='trusted Sparkle 2.10.1 bin directory')
        p.add_argument('--output', type=Path, required=True, help='unused path for the new signed feed')
        if name == 'prepare':
            p.add_argument('--workspace', type=Path, required=True, help='completed release-macos.py workspace')
    modes.add_parser('verify-transition', help='verify the release feed against the actual GitHub event base')
    args = parser.parse_args()
    if args.mode == 'verify-transition':
        verify_github_transition()
        return
    check(not os.path.lexists(args.output), 'refusing to overwrite an existing feed')
    check_host_key(args.tools)
    with tempfile.TemporaryDirectory(prefix='riftlet-appcast-') as name:
        tmp = Path(name)
        if args.mode == 'bootstrap':
            check(not (ROOT / 'updates/stable.xml').exists(), 'initial stable feed already exists in the checkout')
            feed = tmp / 'stable.xml'
            feed.write_bytes(EMPTY)
            tool(args.tools, 'sign_update', str(feed))
            tool(args.tools, 'sign_update', '--verify', str(feed))
            verify(feed)
            check(previous_version(feed) == ((1, 0, 0), 22), 'bootstrap must contain no update')
        else:
            feed = prepare(args, tmp)
        atomic_output(args.output, feed.read_bytes())
    print('Verified signed feed:', args.output)


if __name__ == '__main__':
    try:
        main()
    except (KeyError, OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
