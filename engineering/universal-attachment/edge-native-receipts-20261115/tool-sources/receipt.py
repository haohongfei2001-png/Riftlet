"""Read only the tagged original App callback chain; never infer commercial START.
Only explicit root invocation reads the isolated product trace. Tests use fixtures.
"""
import argparse
import json
import os
import stat

DEFAULT_TRACE = os.path.expanduser('~/Library/Application Support/Riftlet-Isolated-Product-Acceptance/diagnostics/acceptance-recent.jsonl')


def owned(path, limit):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or not 0 < before.st_size < limit:
            raise ValueError('owned_file_identity')
        data = os.read(fd, limit)
        after = os.fstat(fd)
        if len(data) != before.st_size or (before.st_ino,before.st_dev,before.st_size,before.st_mtime_ns) != (after.st_ino,after.st_dev,after.st_size,after.st_mtime_ns):
            raise ValueError('owned_file_changed')
        return data
    finally:
        os.close(fd)


def check(sent, records):
    assert sent['status'] == 'singlePairPostedReceiptNotYetConfirmed'
    asset, window, tag, number = (sent[k] for k in ('assetIDDigest', 'windowNumber', 'mouseProbeTag', 'eventNumber'))
    assert len(asset) == 64 and type(window) is int and window > 0
    assert type(tag) is int and 0 < tag < 1 << 48 and type(number) is int and 1 <= number <= 32767
    assert type(sent['afterDiagnosticSequence']) is int
    rows = [r for r in records if r.get('diagnosticSessionDigest') == sent['diagnosticSessionDigest']
            and type(r.get('diagnosticSequence')) is int and r['diagnosticSequence'] > sent['afterDiagnosticSequence']]
    tagged = [r for r in rows if r.get('mouseProbeTag') == tag]
    valid = all(type(r.get('eventNumber')) is int and r['eventNumber'] == number
                and r.get('windowNumber') == window and r.get('clickCount') == 1 for r in tagged)
    native = [r for r in tagged if r.get('event') == 'mouse_dispatch_boundary']
    valid = valid and all(r.get('assetIDDigest') == asset for r in native)
    applications = [r for r in tagged if r.get('event') == 'mouse_application_event']
    selections = [r for r in tagged if r.get('event') == 'selection_boundary']
    expected = [('windowEvent', 'received', True), ('windowEvent', 'received', False),
                ('inputDown', 'received', True), ('inputUp', 'received', False),
                ('onDown', 'received', True), ('gate', 'accepted', True), ('release', 'selected', False)]
    counts = {f'{p}:{s}:{"down" if d else "up"}':sum(r.get('phase')==p and r.get('status')==s and r.get('mouseDown') is d for r in native)
              for p,s,d in expected}
    complete = (valid and len(tagged) == 10 and len(native) == 7 and all(n == 1 for n in counts.values())
        and len(applications) == 2 and {r.get('phase') for r in applications} == {'down','up'}
        and all(r.get('mouseDown') is (r.get('phase') == 'down') for r in applications)
        and len(selections) == 1 and selections[0].get('source') == 'mouse'
        and selections[0].get('assetIDDigest') == asset and selections[0].get('targetRequested') is True)
    if complete:
        def one(event, **fields):
            found = [r for r in tagged if r.get('event') == event and all(r.get(k) == v for k,v in fields.items())]
            assert len(found) == 1
            return found[0]['diagnosticSequence']
        sequence = [one('mouse_application_event',phase='down'),one('mouse_dispatch_boundary',phase='windowEvent',mouseDown=True),
            one('mouse_dispatch_boundary',phase='inputDown'),one('mouse_dispatch_boundary',phase='onDown'),
            one('mouse_dispatch_boundary',phase='gate'),one('selection_boundary'),one('mouse_application_event',phase='up'),
            one('mouse_dispatch_boundary',phase='windowEvent',mouseDown=False),one('mouse_dispatch_boundary',phase='inputUp'),
            one('mouse_dispatch_boundary',phase='release')]
        complete = all(a < b for a,b in zip(sequence,sequence[1:]))
    selected_seq = selections[0]['diagnosticSequence'] if len(selections)==1 else 0
    next_selection = min((r['diagnosticSequence'] for r in rows if r.get('event')=='selection_boundary'
                         and r.get('assetIDDigest')==asset and r['diagnosticSequence']>selected_seq),default=float('inf'))
    original = [r for r in rows if selected_seq < r['diagnosticSequence'] < next_selection and r.get('assetIDDigest')==asset]
    refusals = [r for r in original if r.get('event')=='click_input_refused']
    submissions = [r for r in original if r.get('event')=='selection_submission_started']
    release_seq = max((r['diagnosticSequence'] for r in native if r.get('phase')=='release'),default=0)
    report = dict(status='EXACT_NATIVE_MOUSE_SELECTION_RECEIPT' if complete else 'UNCONFIRMED_DO_NOT_REPOST',
        uploadStartOrCompletionClaimed=False,exactFieldsMatch=valid,nativeStageCounts=counts,
        applicationEvents=len(applications),selections=len(selections),assetIDDigest=asset,windowNumber=window,
        mouseProbeTag=tag,sentEventNumber=number,attemptID=sent.get('attemptID'),
        receivedEventNumbers=sorted({r.get('eventNumber') for r in tagged if type(r.get('eventNumber')) is int}),
        refusalCount=len(refusals),refusalCodes=[r.get('error','unavailable') for r in refusals],
        explicitPreInputRefusal=(complete and len(refusals)==1 and refusals[0].get('critical') is True
            and refusals[0].get('phase')=='resolveSelection'
            and len(submissions)==1 and release_seq < submissions[0]['diagnosticSequence'] < refusals[0]['diagnosticSequence']
            and not any(r.get('event')=='click_target_resolved' for r in original)))
    return complete, report


def main():
    parser=argparse.ArgumentParser();parser.add_argument('sent');parser.add_argument('--trace',default=DEFAULT_TRACE)
    args=parser.parse_args()
    try:
        sent=json.loads(owned(args.sent,65536));records=[json.loads(s) for s in owned(args.trace,1048576).splitlines()]
        okay,report=check(sent,records);print(json.dumps(report,sort_keys=True));return 0 if okay else 1
    except (OSError,ValueError,KeyError,AssertionError,TypeError):
        print('{"status":"UNCONFIRMED_DO_NOT_REPOST","reason":"receipt_reader_validation_failed"}');return 1


if __name__=='__main__':raise SystemExit(main())
