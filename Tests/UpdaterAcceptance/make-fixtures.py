#!/usr/bin/env python3
"""Prepare localhost-only Sparkle A/B fixtures. No output is suitable for release."""
import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ID = 'com.riftlet.updaterqa.app'
ACCOUNT = ID + '.fixtures'
ORIGIN = 'http://127.0.0.1:48091'
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)


def run(*args):
    return subprocess.check_output(list(map(str, args)), text=True).strip()


def make(args):
    # Product source and signing tools are inputs. Everything written here is new.
    package = args.app.resolve(strict=True)
    if package.name != 'Riftlet.app' or package.parent.name == 'Applications':
        raise ValueError('Use a development package from an isolated build directory.')
    release = plistlib.loads((package/'Contents/Info.plist').read_bytes())
    if release['SUFeedURL'] != 'https://riftlet.com/updates/stable.xml' or release['CFBundleIdentifier'] != 'com.riftlet.app':
        raise ValueError('Unexpected source bundle')
    tools = args.tools.resolve(strict=True)
    key = run(tools/'generate_keys', '--account', ACCOUNT, '-p')
    if len(base64.b64decode(key, validate=True)) != 32 or key == release['SUPublicEDKey']:
        raise ValueError('An independent QA keychain signing identity is required.')
    out = args.output.resolve()
    out.mkdir(exist_ok=False, parents=True)
    spec = importlib.util.spec_from_file_location('sparkle_bundle', ROOT/'scripts/sparkle_bundle.py')
    layout = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(layout)
    with tempfile.TemporaryDirectory(dir=out) as scratch:
        scratch = Path(scratch)
        staging = scratch/'Riftlet.app'
        run('ditto', package, staging)
        for component, _, name in layout.COMPONENTS:
            run('codesign', '--force', '--sign', args.identity, '--identifier', name,
                '--options', 'runtime', '--timestamp', staging/component)
        info = dict(release, CFBundleIdentifier=ID, CFBundleDisplayName='Riftlet QA',
                    SUFeedURL=ORIGIN+'/stable.xml', SUPublicEDKey=key,
                    NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
        for label, build in [('A', 101), ('B', 102)]:
            version = '0.0.' + str(build)
            info.update(CFBundleVersion=str(build), CFBundleShortVersionString=version)
            (staging/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            run('codesign', '--force', '--sign', args.identity, '--options', 'runtime', '--timestamp',
                '--entitlements', ROOT/'packaging/release/Entitlements.plist', staging)
            run('codesign', '--verify', '--deep', '--strict', staging)
            run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', staging, out/(label+'.zip'))
    archive = out/'B.zip'
    good_signature = run(tools/'sign_update', '--account', ACCOUNT, '-p', archive)
    corrupted = bytearray(archive.read_bytes())
    corrupted[len(corrupted)//2] ^= 1
    (out/'corrupt.zip').write_bytes(corrupted)
    # Test rejection of the archive signature with an authentic fixture feed.
    bad_signature = base64.b64encode(b'\x00'*64).decode('ascii')
    for scenario, file, signature, version, build in [
        ('none', None, None, None, None),
        ('available', 'B.zip', good_signature, '0.0.102', '102'),
        ('bad-signature', 'B.zip', bad_signature, '0.0.102', '102'),
        ('corrupt', 'corrupt.zip', good_signature, '0.0.102', '102'),
        ('interrupt', 'interrupted.zip', good_signature, '0.0.102', '102'),
        ('older', 'B.zip', good_signature, '0.0.99', '99'),
        ('older-marketing', 'B.zip', good_signature, '0.0.100', '102'),
    ]:
        rss = ET.Element('rss', version='2.0')
        channel = ET.SubElement(rss, 'channel')
        ET.SubElement(channel, 'title').text = 'Riftlet Update QA'
        ET.SubElement(channel, 'link').text = ORIGIN
        ET.SubElement(channel, 'description').text = 'Local test only'
        if file:
            item = ET.SubElement(channel, 'item')
            ET.SubElement(item, 'title').text = 'Riftlet QA ' + version
            ET.SubElement(item, 'description').text = 'Local acceptance: preserve screenshot history.'
            for name, value in [('version', build), ('shortVersionString', version), ('minimumSystemVersion', '13.0')]:
                ET.SubElement(item, '{'+NS+'}'+name).text = value
            ET.SubElement(item, 'enclosure', {'url': ORIGIN+'/'+file, 'length': str(archive.stat().st_size),
                          'type': 'application/octet-stream', '{'+NS+'}edSignature': signature})
        path = out/(scenario+'.xml')
        ET.ElementTree(rss).write(path, encoding='utf-8', xml_declaration=True)
        run(tools/'sign_update', '--account', ACCOUNT, path)
        run(tools/'sign_update', '--account', ACCOUNT, '--verify', path)
    forged = (out/'available.xml').read_bytes().replace(b'Local acceptance:', b'Other acceptance:')
    (out/'invalid-feed.xml').write_bytes(forged)
    shutil.copy(out/'none.xml', out/'stable.xml')
    print(json.dumps({'bundleID': ID, 'loopback': ORIGIN, 'output': str(out), 'archives': {
        name: hashlib.sha256((out/name).read_bytes()).hexdigest() for name in ['A.zip', 'B.zip']}}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--tools', required=True, type=Path)
    parser.add_argument('--identity', required=True, help='Local Developer ID Application fingerprint')
    parser.add_argument('--output', required=True, type=Path)
    make(parser.parse_args())
