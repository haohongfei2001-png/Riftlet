"""Audit one real build 59 native seed and its stopped continuation. Read-only."""
import argparse
import base64
import hashlib
import json
from pathlib import Path


def check(ok, why):
    if not ok:
        raise ValueError(why)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def one(rows, **fields):
    matches = [row for row in rows if all(row.get(k) == v for k, v in fields.items())]
    check(len(matches) == 1, f"Expected one {fields}")
    return matches[0]


def audit(original, continuation):
    hashes = {}

    def data(directory, filename):
        raw = (directory / filename).read_bytes()
        group = 'seed' if directory == original else 'continuation'
        hashes[f'{group}/{filename}'] = sha(raw)
        return raw

    def read(directory, filename):
        return json.loads(data(directory, filename))

    def envelope(directory, name):
        wrapper = read(directory, name)
        b = base64.b64decode(wrapper['payloadBase64'], validate=True)
        check(sha(b) == wrapper['sha256'] and json.loads(b) == wrapper['payload'], 'Native receipt hash mismatch')
        return wrapper['payload']

    def trace(directory):
        out = []
        for line in data(directory, 'candidate.stderr').splitlines():
            if line.startswith(b'{'):
                out.append(json.loads(line))
        return out

    child = read(original, 'child.json')
    family = read(original, 'result.json')['family']
    installed = child['candidate']
    check(installed['build'] == '59' and installed['sha256'] ==
          '666324176aadc4ffb9fd6fbfd0ca38772a169eb06394401f7abede374f7d3ee6', 'Wrong installed candidate')
    res = read(continuation, 'result.json')
    resumed = read(continuation, 'child.json')
    check(resumed['candidate'] == installed and resumed['profile'] == child['profile'] and
          child['pid'] != resumed['pid'] and res['family'] == family and res['status'] == 'STOPPED' and
          res['privateChildExited'] is True and res['completedBatches'] == [], 'Unverified first continuation')
    db = read(original, 'final-db.json')
    op, = db['operations']
    asset, = db['assets']
    newdb = read(continuation, 'final-db.json')
    returned, = newdb['operations']
    returned_asset, = newdb['assets']
    keys = ('id', 'assetID', 'invocationID', 'clickBindingID', 'originalDocumentID', 'originalComposerID',
            'originalDraftGeneration', 'currentAttachmentID', 'uniqueStartEvidence', 'durableStartedAt')
    check(all(op[k] and op[k] == returned[k] for k in keys) and op['startMatchesOriginal'] and
          returned['startMatchesOriginal'] and op['startCount'] == returned['startCount'] == 1 and
          op['startSignal'] == returned['startSignal'] == 'attachmentAccepted' and
          (asset['assetID'], asset['sha256']) == (returned_asset['assetID'], returned_asset['sha256'])
          and not op['hasError'] and not returned['hasError'], 'Original durable START changed')
    proof, = read(original, 'positive-1.json')
    click = read(original, 'click-1.json')
    captured = read(original, 'capture-1.json')
    check(captured['systemScreenshotMarker'] and captured['ownerVerified'] and captured['browserStillForeground'] and
          click['delivery'] == 'MOUSE_DOWN_ACKNOWLEDGED' and
          captured['sha256'] == asset['sha256'] == click['sha256'] == proof['sha256'] and
          op['id'] == proof['operationID'] and op['invocationID'] == proof['invocationID'] and
          proof['cardID'] == op['currentAttachmentID'] and proof['evidenceID'] == op['uniqueStartEvidence'], 'Wrong original image or receipt')
    auth = envelope(original, 'native-auth-press-1.json')
    future = envelope(continuation, 'native-auth-batch-2.json')
    check(all(auth.get(k) == future.get(k) for k in ['family', 'pid', 'bundle', 'sessionID', 'windowID', 'tabID']) and
          auth['family'] == family and all(auth['page'].get(k) == future['page'].get(k) for k in ['entryID','timeOrigin']) and
          all(r[k] for r in [auth, future] for k in ['dynamicSignature', 'originalSoleTab', 'originalSelection', 'exactTemporaryURL', 'systemForeground']) and
          all(r['page']['signedIn'] and r['page']['editor'] and r['page']['uploadEntry'] and r['page']['authSignals']['bootstrapStatus'] == 'logged_in' for r in [auth,future]), 'Original Temporary Chat or account check failed')
    page = read(original, 'page-after-1.json')
    after = read(continuation, 'final-page.json')
    receipts = page['observedInputReceipts']
    counts = {'fileInput':1, 'fileChange':1, 'formSubmit':0, 'sendButtonClicks':0}
    check(page['counts'] == after['counts'] == counts and page['files'] == after['files'] and
          len(page['files']) == 1 and page['files'][0]['decoded'] and
          [r['event'] for r in receipts] == ['input','change'] and
          all(r['sha256'] == proof['sha256'] and r['sameInputAsOriginal'] for r in receipts) and
          all(r['originalDocument'] and r['originalEditor'] for r in [page,after]), 'Original file receipt changed')
    pixels, = [x for x in page['pixelEvidence'] if x['file'] and x['file'] == x['decoded'] and x['decoded']['digest'] == proof['pixelsSHA256']]
    check(pixels['forLastInput'].lower() == proof['inputName'].lower(), 'Original pixels not attributed')
    original_events = trace(original)
    down = one(original_events, event='selection_boundary', source='mouse')
    check(not any(r.get('event') == 'selection_boundary' for r in trace(continuation)), 'A further selection was posted')
    check(down['eventNumber'] == click['eventNumber'] == proof['eventNumber'] and
          down['eventUptime'] == click['eventUptime'] == proof['downUptime'] and
          sha(op['id'].lower().encode()) == one(original_events, event='preclick_lease', phase='consumed',
                                                 requestIDDigest=proof['requestDigest'])['operationIDDigest'], 'Signed selection did not join')
    armed = one(original_events, event='preclick_lease', phase='armed', requestIDDigest=proof['requestDigest'])
    frozen = one(original_events, event='preclick_lease', phase='frozen', requestIDDigest=proof['requestDigest'])
    check(frozen['originalEventUptime'] == down['eventUptime'] and armed['acknowledgedUptime'] == proof['ackUptime'] < down['eventUptime'],
          'No earlier signed ACK')
    commit = one(original_events, event='native_bridge', action='commit', phase='complete', transportSucceeded=True)
    handed = one(original_events, event='attachment_entry_result', phase='inputTriggered')
    start = one(original_events, event='attachment_entry_result', phase='uploadStarted')
    check(handed['setterEntered'] and handed['changeReturned'] and start['startObserved'], 'File setter or start report missing')
    def relative(value): return round((value - down['eventUptime']) * 1000, 3)
    def boundary(phase): return relative(one(original_events, event='presentation_boundary', phase=phase)['uptime'])
    rgb = read(original, 'source-pixels-1.json')
    check(rgb['sha256'] == proof['sha256'] and rgb['uniqueAgainstPriorSources'], 'Source uniqueness missing')
    termination = {'reason':res['reason'], 'newMouseDowns':0, 'newInputs':0, 'originalStartPreserved':True}
    local_result = continuation/'capture-2.json'
    if local_result.is_file():
        result = read(continuation, local_result.name)
        check(result == {'exit':1,'reason':'NO_JSON'}, 'Unknown capture result')
        termination['captureHelper'] = result
    return {'family':family, 'candidate':installed, 'status':'OBSERVED_SINGLE_SEED',
            'rapidPairsObserved':0, 'explicitFailureCardObserved':False, 'counts':counts,
            'originalFileAndDecodedPreviewMatched':True, 'nextAttempt':termination,
            'hostMSRelativeToMouseDown':{'ack':relative(armed['acknowledgedUptime']), 'mouseDown':0,
                'appKitCallback':relative(down['callbackUptime']),
                'commitInterval':[relative(commit['startedUptime']),relative(commit['endedUptime'])],
                'setterEnteredAndChangeReturnedReported':relative(handed['uptime']),
                'attachmentAcceptedReported':relative(start['uptime']),
                'swallowStart':boundary('swallowActualStart'),'swallowEnd':boundary('swallowClose')},
            'browserDocumentClockMS':{'input':receipts[0]['atMS'],'change':receipts[1]['atMS'],
                                      'observedSetterEntry':receipts[0].get('productSetterEntryMS')},
            'originalPrivateReceiptsSHA256':hashes}


if __name__=='__main__':
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument('original',type=Path)
    cli.add_argument('continuation',type=Path)
    args=cli.parse_args()
    print(json.dumps(audit(args.original, args.continuation), sort_keys=True, indent=2, allow_nan=False))
