#!/usr/bin/env python3
"""Offline stable-feed tests; the official verification key is public."""
import base64
import copy
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('appcast', Path(__file__).with_name('release-appcast.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class StableFeedTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix='riftlet-feed-test-')
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)

    def test_authenticated_metadata_is_read_only_and_scoped_to_the_release_repository(self):
        with mock.patch.dict(os.environ, {'RIFTLET_APPCAST_GH_AUTH': '1'}), \
                mock.patch.object(subprocess, 'check_output', return_value=b'{"immutable":true}') as cli:
            self.assertEqual(m.git_api('/releases/tags/v1.0.1'), {'immutable': True})
        cli.assert_called_once_with(['gh', 'api', '--hostname', 'github.com', '--method', 'GET',
                                     'repos/' + m.REPO + '/releases/tags/v1.0.1'], timeout=40)

    def test_public_key_alone_verifies_signed_repository_feed(self):
        feed = m.ROOT / 'updates/stable.xml'
        m.verify(feed)
        self.assertGreaterEqual(m.previous_version(feed), ((1, 0, 0), 22))
        copy_feed = self.root / 'changed.xml'
        copy_feed.write_bytes(feed.read_bytes().replace(b'Riftlet', b'Riftler'))
        with self.assertRaises(subprocess.CalledProcessError):
            m.verify(copy_feed)
        copy_feed.write_bytes(feed.read_bytes().split(b'<!-- sparkle-signatures:')[0])
        with self.assertRaises(subprocess.CalledProcessError):
            m.verify(copy_feed)
        info = plistlib.loads(m.INFO.read_bytes())
        info['SUPublicEDKey'] = base64.b64encode(b'X' * 32).decode()
        plist = self.root / 'Info.plist'
        plist.write_bytes(plistlib.dumps(info))
        with mock.patch.object(m, 'INFO', plist), self.assertRaises(subprocess.CalledProcessError):
            m.verify(feed)

    def test_downloading_always_requires_signed_feed(self):
        info = plistlib.loads(m.INFO.read_bytes())
        m.check_host_policy(info)
        for value in (None, False, 7, -10):
            with self.subTest(interval=value), self.assertRaises(ValueError):
                m.check_host_policy(dict(info, SUSignedFeedFailureExpirationInterval=value))

    def test_stable_upgrade_orders_both_numbers_numerically(self):
        last = ((1, 0, 9), 28)
        m.require_successor(last, '1.0.10', '29')
        for v, b in [('1.0.10', '28'), ('1.0.9', '29'), ('1.0.8', '30'), ('1.1.0', '24'),
                     ('1.0.10-beta', '30'), ('1.0.09', '30'), ('1.1.0', '0'), ('1.1.0', '30.5')]:
            with self.subTest(v=v, b=b), self.assertRaises(ValueError):
                m.require_successor(last, v, b)

    def test_requires_immutable_published_hashed_versioned_asset(self):
        v = '1.0.1'
        size = 412
        digest = 'a' * 64
        url = m.WEB + '/releases/download/v1.0.1/Riftlet-1.0.1.dmg'
        asset = dict(name='Riftlet-1.0.1.dmg', state='uploaded', size=size, digest='sha256:' + digest, browser_download_url=url)
        release = dict(tag_name='v1.0.1', draft=False, prerelease=False, immutable=True, published_at='2026-11-14',
                       body='Signed description', assets=[asset])
        with mock.patch.object(m, 'git_api', return_value=release):
            self.assertEqual(m.published_release(v, digest, size), (url, 'Signed description'))
        bad = [dict(release, **{k: val}) for k, val in [('draft', True), ('prerelease', True), ('immutable', False),
               ('tag_name', 'v1.0.2'), ('published_at', None), ('assets', [asset, asset]), ('assets', [])]]
        bad.extend(dict(release, assets=[dict(asset, **{k: val})]) for k, val in
                   [('size', 999), ('digest', None), ('state', 'new'), ('browser_download_url', 'https://example.org/app.dmg')])
        for i, snapshot in enumerate(bad):
            with self.subTest(case=i), mock.patch.object(m, 'git_api', return_value=snapshot), self.assertRaises(ValueError):
                m.published_release(v, digest, size)

    def test_admission_only_tag_delta(self):
        first, second = '1' * 40, '2' * 40
        main = '3' * 40
        ancestry = [{'object': {'sha': main}}, {'merge_base_commit': {'sha': second}, 'status': 'ahead'}]
        response = {'merge_base_commit': {'sha': first}, 'files': [{'filename': 'engineering/mainline/source-admission.json'}]}
        with mock.patch.object(m, 'git_api', side_effect=[{'sha': second}, *ancestry, response]):
            m.source_matches(first, 'v1.0.1')
        response['files'].append({'filename': 'Sources/RiftletApp/Main.swift'})
        with mock.patch.object(m, 'git_api', side_effect=[{'sha': second}, *ancestry, response]), self.assertRaises(ValueError):
            m.source_matches(first, 'v1.0.1')

    def test_source_equal_to_tag_outside_main_is_rejected(self):
        source, main = '1' * 40, '2' * 40
        replies = [{'sha': source}, {'object': {'sha': main}},
                   {'merge_base_commit': {'sha': '3' * 40}, 'status': 'diverged'}]
        with mock.patch.object(m, 'git_api', side_effect=replies), self.assertRaisesRegex(ValueError, 'main history'):
            m.source_matches(source, 'v1.0.1')

    def test_ci_feed_transition_checks_first_release_and_rollback(self):
        from xml.etree import ElementTree as ET
        def feed(v=None, b=None):
            p = self.root / ((v or 'empty') + '-' + str(b) + '.xml')
            root = ET.fromstring(m.EMPTY)
            if v is not None:
                item = ET.SubElement(root.find('channel'), 'item')
                ET.SubElement(item, m.NS + 'version').text = b
                ET.SubElement(item, m.NS + 'shortVersionString').text = v
            ET.ElementTree(root).write(p)
            return p
        # Signature verification itself is exercised by the previous independent public-key test.
        empty, current, future = feed(), feed('1.0.1', '23'), feed('1.0.2', '24')
        with mock.patch.object(m, 'verify'):
            for previous, new in [(None, empty), (empty, empty), (empty, current), (current, current), (current, future)]:
                m.verify_transition(previous, new)
            for previous, new in [(None, current), (future, current), (future, empty),
                                  (future, feed('1.0.3', '24')), (future, feed('1.0.2', '25'))]:
                with self.subTest(previous=previous, new=new), self.assertRaises(ValueError):
                    m.verify_transition(previous, new)

    def test_feed_contract_rejects_unrelated_target_forced_update_and_missing_notes(self):
        import xml.etree.ElementTree as ET
        data = ET.fromstring(m.EMPTY)
        item = ET.SubElement(data.find('channel'), 'item')
        sig = base64.b64encode(b'S' * 64).decode()
        nodes = [('link', 'https://riftlet.com/'), (m.NS + 'version', '23'), (m.NS + 'shortVersionString', '1.0.1'),
                 (m.NS + 'minimumSystemVersion', '13.0')]
        for key, text in nodes:
            ET.SubElement(item, key).text = text
        ET.SubElement(item, 'description', {m.NS + 'format': 'plain-text'}).text = 'Notes'
        ET.SubElement(item, 'enclosure', {'type': 'application/octet-stream', 'length': '412', m.NS + 'edSignature': sig,
                                          'url': m.WEB + '/releases/download/v1.0.1/Riftlet-1.0.1.dmg'})
        dest = self.root / 'feed.xml'
        ET.ElementTree(data).write(dest)
        self.assertEqual(m.validate_item(dest, '1.0.1', '23', 412, 'Notes'), sig)
        for child in ['criticalUpdate', 'channel', 'deltas', 'releaseNotesLink', 'informationalUpdate']:
            modified = copy.deepcopy(data)
            ET.SubElement(modified.find('channel/item'), m.NS + child)
            ET.ElementTree(modified).write(dest)
            with self.subTest(child=child), self.assertRaises(ValueError):
                m.validate_item(dest, '1.0.1', '23', 412, 'Notes')
        for key, text in [('url', 'https://example.org/alternate'), ('length', '419')]:
            modified = copy.deepcopy(data)
            modified.find('channel/item/enclosure').set(key, text)
            ET.ElementTree(modified).write(dest)
            with self.assertRaises(ValueError):
                m.validate_item(dest, '1.0.1', '23', 412, 'Notes')
        item.remove(item.find('description'))
        ET.ElementTree(data).write(dest)
        with self.assertRaises(ValueError):
            m.validate_item(dest, '1.0.1', '23', 412, 'Notes')

    @unittest.skipUnless(os.environ.get('RIFTLET_SPARKLE_TEST_BIN'), 'set RIFTLET_SPARKLE_TEST_BIN for real DMG integration')
    def test_official_generator_and_corruption_with_ephemeral_test_identity(self):
        tools = Path(os.environ['RIFTLET_SPARKLE_TEST_BIN'])
        source = self.root / 'source'
        app = source / 'Riftlet.app'
        binary = app / 'Contents/MacOS/Riftlet'
        binary.parent.mkdir(parents=True)
        shutil.copy('/usr/bin/true', binary)
        # This seed is ephemeral and goes only to official CLI on stdin. The release Keychain is never accessed.
        seed = os.urandom(32)
        input_key = base64.b64encode(seed) + b'\n'
        derive_public = ('import CryptoKit; import Foundation; '
                         'let data = FileHandle.standardInput.readDataToEndOfFile(); '
                         'print(try Curve25519.Signing.PrivateKey(rawRepresentation: data).publicKey.'
                         'rawRepresentation.base64EncodedString())')
        key = subprocess.check_output(['xcrun', 'swift', '-e', derive_public], input=seed).decode().strip()
        plist = app / 'Contents/Info.plist'
        plist.write_bytes(plistlib.dumps({
            'CFBundleExecutable': 'Riftlet', 'CFBundleName': 'Riftlet', 'CFBundlePackageType': 'APPL',
            'CFBundleIdentifier': 'invalid.test.RiftletFeedOnly', 'CFBundleVersion': '24',
            'CFBundleShortVersionString': '1.0.2', 'LSMinimumSystemVersion': '13.0',
            'SURequireSignedFeed': True, 'SUFeedURL': 'https://example.invalid/update-test.xml', 'SUPublicEDKey': key,
        }))
        subprocess.run(['codesign', '--force', '--sign', '-', app], check=True)
        archives = self.root / 'archives'
        archives.mkdir()
        dmg = archives / 'Riftlet-1.0.2.dmg'
        subprocess.run(['hdiutil', 'create', '-format', 'UDZO', '-fs', 'HFS+', '-volname', 'Riftlet-Feed-QA',
                        '-srcfolder', source, dmg], check=True)
        notes = 'Update test only. 更新测试。'
        dmg.with_suffix('.txt').write_text(notes)
        feed = archives / 'stable.xml'
        for name in ['generate_appcast', 'sign_update']:
            self.assertEqual(m.sha(tools / name), m.TOOL_SHA[name])
        subprocess.run([tools / 'generate_appcast', '--ed-key-file', '-', '--download-url-prefix',
                        m.WEB + '/releases/download/v1.0.2/', '--link', 'https://riftlet.com/',
                        '--maximum-deltas', '0', '--versions', '24', '--embed-release-notes', '-o', feed, archives],
                       input=input_key, check=True)
        signature = m.validate_item(feed, '1.0.2', '24', dmg.stat().st_size, notes)
        with mock.patch.object(m, 'INFO', plist):
            for path, sig in [(feed, []), (dmg, [signature])]:
                subprocess.run([tools / 'sign_update', '--verify', '--ed-key-file', '-', path, *sig],
                               input=input_key, check=True)
                m.verify(path, *sig)
            with dmg.open('ab') as output:
                output.write(b'altered')
            with self.assertRaises(subprocess.CalledProcessError):
                m.verify(dmg, signature)
            with dmg.open('r+b') as output:
                output.truncate(dmg.stat().st_size // 2)
            with self.assertRaises(subprocess.CalledProcessError):
                m.verify(dmg, signature)
            with self.assertRaises(subprocess.CalledProcessError):
                m.verify(dmg, base64.b64encode(b'X' * 64).decode())

    def test_signing_output_cannot_overwrite_existing_or_symlink(self):
        target = self.root / 'stable.xml'
        m.atomic_output(target, b'first')
        with self.assertRaises(FileExistsError):
            m.atomic_output(target, b'second')
        alias = self.root / 'alias'
        alias.symlink_to(target)
        with self.assertRaises(FileExistsError):
            m.atomic_output(alias, b'third')
        self.assertEqual(target.read_bytes(), b'first')


if __name__ == '__main__':
    unittest.main()
