"""Cross-check the build 59 Edge calibration from its retained original evidence."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
from uuid import UUID

from audit_history import require
from verify_recovery import read_operation, snapshot

CANDIDATE = '666324176aadc4ffb9fd6fbfd0ca38772a169eb06394401f7abede374f7d3ee6'
PRODUCT = '69b76cb025ab552b3480e3af095b627891874712'
SAMPLER = '8f5add018ef46edcb232ef3340340924068c85ea5e7cccf97bf6a21a33693351'
ATTEMPTS = ('preclick-calibration-admission-1', 'preclick-calibration-admission-2', 'live-g4-calibration')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    return json.loads(path.read_bytes())


def single(items):
    item, = items
    return item


def native_scope(path, route, entry):
    wrapper = read(path)
    original = base64.b64decode(wrapper['payloadBase64'], validate=True)
    native = wrapper['payload']
    page = native['page']
    require(sha(original) == wrapper['sha256'] and json.loads(original) == native, 'Invalid native packet')
    require((native['bundle'], native['sessionID'], native['windowID'], native['tabID']) ==
            (route['applicationID'], route['session'], route['windowID'], route['tabID']) and
            all(native.get(k) is True for k in ('dynamicSignature', 'originalSelection', 'originalSoleTab',
                                                'systemForeground', 'exactTemporaryURL')) and
            all(page.get(k) is True for k in ('editor', 'signedIn', 'uploadEntry')) and
            page['authSignals']['bootstrapStatus'] == 'logged_in' and
            (page['entryID'], page['timeOrigin']) == (entry['entryID'], entry['timeOrigin']),
            'Original authenticated document changed')


def examine(directory, backup, profile_parent):
    candidate = read(directory/'child.json')
    identity = candidate['profile']
    require(str(UUID(identity)) == identity and candidate['candidate']['sha256'] == CANDIDATE and
            candidate['candidate']['source'] == PRODUCT and candidate['candidate']['build'] == '59',
            'Wrong candidate or QA profile')
    profile = profile_parent/('Riftlet-PreClick-QA-' + identity)
    require(profile.resolve() == profile and (profile/'settings-review-identity.txt').read_text().strip() == identity,
            'Wrong isolated profile')
    trace = [json.loads(s) for s in (directory/'candidate.stderr').read_bytes().splitlines() if s.startswith(b'{')]
    page = read(directory/'final-page.json')
    counts = page['counts']
    db_copy = read(directory/'final-db.json')
    route = read(directory/'route.json')
    entry = read(directory.parent/'original-entry.json')
    native_scope(directory/'native-auth-startup.json', route, entry)
    require(route['applicationID'] == 'com.microsoft.edgemac' and page['originalDocument'] and page['originalEditor']
            and counts['formSubmit'] == counts['sendButtonClicks'] == 0, 'Wrong browser or original page')
    presses = [e for e in trace if e['event'] == 'selection_boundary']
    commits = [e for e in trace if e['event'] == 'native_bridge' and e.get('action') == 'commit']
    require(read(directory/'result.json')['privateChildExited'] and read(directory/'watch-closed.json')['closed'],
            'Unclosed calibration run')
    outcome = {
        'attempt': directory.name,
        'sha256ByPrivateSource': {p.name: sha(p.read_bytes()) for p in sorted(directory.iterdir())
                                  if p.is_file() and p.suffix in ('.json', '.stderr')},
        'standaloneCalibrationBackupSHA256': sha(backup.read_bytes()),
        'nativeMouseDowns': len(presses), 'nativeCommits': len(commits), 'websiteCounts': counts,
    }
    with snapshot(backup) as db:
        totals = {t: db.execute('SELECT count(*) FROM ' + t).fetchone()[0]
                  for t in ('assets', 'operations', 'upload_starts')}
        outcome['databaseCounts'] = totals
        require(len(db_copy['operations']) == totals['operations'] and len(db_copy['assets']) == totals['assets'],
                'SQLite and final driver view differ')
        if not totals['operations']:
            require(not presses and not commits and totals['upload_starts'] == 0 and not counts['fileInput'] and
                    not counts['fileChange'] and not page['observedInputReceipts'] and not page['files'] and
                    not (directory/'calibration-click-intent.json').exists(), 'A stopped admission reached input')
            outcome['stop'] = read(directory/'result.json')['reason']
            if (directory/'main-world-arm.json').exists():
                outcome['samplerRefusal'] = read(directory/'main-world-arm.json')['reason']
            return outcome
        native_scope(directory/'calibration-native-before-click.json', route, entry)
        require(totals == {'assets': 1, 'operations': 1, 'upload_starts': 1} and counts['fileInput'] ==
                counts['fileChange'] == len(presses) == len(commits) == 1, 'Unexpected calibration counts')
        oid, = db.execute('SELECT id FROM operations').fetchone()
        op = single(db_copy['operations'])
        row = read(directory/'row-1.json')
        capture = read(directory/'capture-1.json')
        require(row['state'] == 'VERIFIED_READ_ONLY' and row['eventsPosted'] == 0 and capture['systemScreenshotMarker']
                and capture['ownerVerified'] and capture['browserStillForeground'], 'System screenshot not proven')
        src = profile/'capture-source'/capture['fileName']
        media = profile/'media'/(row['assetID'].lower() + '.png')
        require(src.resolve() == src and media.resolve() == media, 'Wrong private PNG path')
        png = src.read_bytes()
        require(png == media.read_bytes() and sha(png) == capture['sha256'] == row['sha256'], 'Original PNG changed')
        stored = read_operation(db, oid, png)
        require(stored['start'] and stored['call']['invocationID'] == op['invocationID'] and oid == op['id']
                and stored['identity']['assetID'] == op['assetID'] == row['assetID'], 'SQLite identity changed')
    click = read(directory/'click-1.json')
    binding = read(directory/'calibration-binding.json')
    target = stored['identity']['target']
    request = sha(target['clickBindingID'].lower().encode('ascii'))
    mouse = single(presses)
    require(click['delivery'] == 'MOUSE_DOWN_ACKNOWLEDGED' and mouse['source'] == 'mouse' and
            click['assetID'] == row['assetID'] and mouse['assetIDDigest'] == sha(row['assetID'].lower().encode()) and
            mouse['eventNumber'] == click['eventNumber'] and mouse['eventUptime'] == click['eventUptime'] and
            request == binding['preparedLeaseDigest'] and binding['assetID'] == row['assetID'] and
            (target['sessionID'], target['windowID'], target['tabID'], target['applicationID']) ==
            (route['session'], route['windowID'], route['tabID'], route['applicationID']), 'Native binding changed')
    leases = [e for e in trace if e['event'] == 'preclick_lease' and e.get('requestIDDigest') == request]
    phase = {k: single(e for e in leases if e['phase'] == k) for k in ('armed', 'frozen', 'consumed')}
    op_hash = sha(oid.lower().encode('ascii'))
    require(phase['armed']['acknowledgedUptime'] == binding['preparedLeaseAckUptime'] < mouse['eventUptime'] and
            phase['frozen']['originalEventUptime'] == mouse['eventUptime'] and
            phase['consumed']['operationIDDigest'] == op_hash, 'Wrong pre-click ACK/consumption')
    receipt = page['observedInputReceipts']
    name = 'riftlet-' + oid.lower() + '.png'
    require([r['event'] for r in receipt] == ['input', 'change'] and
            all(r['knownQAFileName'].lower() == name and r['sha256'] == sha(png) and r['bytes'] == len(png)
                and r['sameInputAsOriginal'] and r['fromOriginalForm'] for r in receipt), 'Site File input changed')
    pixels = single(page['pixelEvidence'])
    require(pixels['forLastInput'].lower() == name and pixels['file'] == pixels['decoded'] and
            pixels['file']['digest'] == read(directory/'source-pixels-1.json')['rgbaSHA256'] and
            all(not c['uniqueNamedCard'] for c in page['g4ErrorCards']), 'Wrong original preview or failed card')
    arm, sample, finish = [read(directory/n) for n in ('main-world-arm.json', 'calibration-passive-sample.json',
                                                       'calibration-passive-finish.json')]
    require(arm['status'] == 'ARMED' and sample['status'] == 'OBSERVING' and finish['status'] == 'CALIBRATED' and
            all(sample[k] == finish[k] for k in finish if k not in ('status', 'restored')) and
            finish['reason'] is None and finish['requestPending'] is False and
            all(finish[k] is True for k in ('restored', 'sourceVerified', 'bytesVerified', 'sameFile',
                                            'byteReturned', 'byteCompleted')) and
            finish['pending'] == finish['observerPending'] == finish['cancelledByObserver'] == 0 and
            all(type(finish[k]) is int and finish[k] == 1 for k in ('inputs','changes','creates','responses','byteRequests'))
            and finish['operationHash'] == op_hash, 'Incomplete passive network attribution')
    create, put = finish['create'], finish['bytes']
    require(create == {'fileNameField':'file_name', 'method':'POST', 'path':'/backend-api/files',
                       'responseStatus':200, 'transport':'fetch', 'uploadURLField':'upload_url',
                       'urlSHA256':sha(b'https://chatgpt.com/backend-api/files')} and
            (put['method'], put['transport'], put['bodyType'], put['bodyScope'], put['responseStatus']) ==
            ('PUT','xhr','File','entire-body',201) and put['bodySize'] == put['pngBytes'] == len(png) and
            put['pngSHA256'] == sha(png) and len(bytes.fromhex(put['urlSHA256'])) == 32,
            'Incomplete native HTTP/PNG attribution')
    outcome.update({'samePNGFileObject': True, 'originalPNGBytes': len(png), 'operationIDDigest': op_hash,
                    'pngSHA256': sha(png), 'decodedOriginalCardPixelsSHA256': pixels['file']['digest'],
                    'create': create, 'upload': put, 'nativeRequestReturnedAndCompleted': True,
                    'observerRestored': True, 'originalNamedFailedCards': 0, 'faultsApplied': 0})
    return outcome


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ('edge_state', 'audit_backup_root', 'profile_parent', 'sampler_js', 'native_host'):
        parser.add_argument(arg, type=Path)
    args = parser.parse_args()
    source = args.sampler_js.read_bytes()
    binary = args.native_host.read_bytes()
    require(sha(source) == SAMPLER and source.strip().rstrip(b';') in binary, 'Frozen sampler not in native host')
    runs = [examine(args.edge_state/sub, args.audit_backup_root/sub/'audit.sqlite', args.profile_parent)
            for sub in ATTEMPTS]
    require([r['nativeMouseDowns'] for r in runs] == [0, 0, 1], 'Unexpected original input order')
    print(json.dumps({'scope':'Passive calibration only', 'browser':'Edge', 'dmgSHA256':CANDIDATE,
                      'productCommit':PRODUCT, 'samplerSHA256':SAMPLER, 'nativeHostSHA256':sha(binary),
                      'attempts':runs, 'calibration':'PASS', 'controlledFault':'NOT_RUN',
                      'originalFailureAndRecovery':'NOT_RUN', 'beforeAfterRecoverySnapshots':'NOT_RUN'},
                     indent=2, sort_keys=True))
