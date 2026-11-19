"""No native UI, browser, database or network is opened by these fixtures."""
from copy import deepcopy
import hashlib
import json
from settled import classify, digest_id

def fixture():
    targets = {'AAAAAAAA-0000-4000-8000-000000000001': 101,
               'AAAAAAAA-0000-4000-8000-000000000002': 102}
    operations = [(asset, 'BBBBBBBB-0000-4000-8000-00000000000' + str(i))
                  for i, asset in enumerate(targets, 1)]
    senders, reservations, intents, trace = {}, {}, {}, []
    attempt, binary, session = 'neutral-pair', 'a' * 64, 'b' * 64
    for i, (asset, seed) in enumerate(targets.items(), 1):
        seq = (i - 1) * 4
        sender = dict(assetIDDigest=digest_id(asset), attemptID=attempt,
                      configurationSHA256='c' * 64, diagnosticSessionDigest=session,
                      eventNumber=i * 100, mouseProbeTag=i * 1000,
                      productBinarySHA256=binary, afterDiagnosticSequence=seq)
        senders[seed] = {**sender, 'status': 'singlePairPostedReceiptNotYetConfirmed'}
        reservations[seed] = {**sender, 'status': 'reservedBeforePost'}
        intents[seed] = {'ordinal': i, 'target': digest_id(asset)}
        common = dict(diagnosticSessionDigest=session, assetIDDigest=digest_id(asset))
        for event, offset, extra in [
            ('mouse_application_event', 1, {'phase': 'down'}),
            ('selection_boundary', 2, {}),
            ('mouse_application_event', 3, {'phase': 'up'}),
        ]:
            trace.append(dict(common, event=event, diagnosticSequence=seq + offset,
                              mouseProbeTag=i * 1000, eventNumber=i * 100, **extra))
        trace.append(dict(common, event='attachment_entry_result',
                          diagnosticSequence=seq + 4,
                          operationIDDigest=digest_id(operations[i - 1][1]),
                          setterEntered=True, changeReturned=True))
    return dict(allowed_seeds={101,102},targets=targets, operations=operations, trace=trace, senders=senders,
                reservations=reservations, intents=intents, attempt=attempt, binary=binary)

def refused(data, seed, phase='resolveSelection'):
    asset, = [a for a, s in data['targets'].items() if s == seed]
    data['operations'] = [(a, o) for a, o in data['operations'] if a != asset]
    for row in data['trace']:
        if row.get('event') == 'attachment_entry_result' and row['assetIDDigest'] == digest_id(asset):
            row.update(event='click_input_refused', phase=phase)
            for k in ['setterEntered', 'changeReturned', 'operationIDDigest']:
                row.pop(k)

def run():
    import identity as early
    names = []
    def check(label, mutation=lambda d: None, expect='ready2', reason=None):
        d = fixture(); mutation(d)
        try:
            got = classify(**d)
        except ValueError as exc:
            if expect != 'reject':
                raise
            if reason is not None:
                assert str(exc) == reason, (label, str(exc))
        else:
            if expect == 'pending':
                assert got is None, label
            elif expect == 'reject':
                raise AssertionError(label + ': false acceptance')
            else:
                count = int(expect[-1]); assert got is not None and got['observedOperationCount'] == count, label
                assert got['takeNativeUI'] == bool(count) and not got['newInputOrRetryAuthorized'], label
        names.append(label)
    check('two_original_changes')
    check('first_refused_second_change', lambda d: refused(d, 101), 'ready1')
    check('second_refused_first_change', lambda d: refused(d, 102), 'ready1')
    check('both_refused_no_UI', lambda d: [refused(d, s) for s in [101, 102]], 'ready0')
    check('second_not_selected_no_UI', lambda d: d.update(trace=d['trace'][:4], operations=d['operations'][:1]), 'pending')
    check('second_sender_absent_no_UI', lambda d: d['senders'].pop(102), 'pending')
    check('second_unknown_no_UI', lambda d: [d.update(operations=d['operations'][:1]), d['trace'][-1].update(changeReturned=False)], 'pending')
    check('submitSelection_is_not_preinput', lambda d: refused(d, 101, 'submitSelection'), 'pending')
    check('setter_entered_reply_uncertain_no_UI', lambda d: d['trace'][-1].update(changeReturned=False), 'pending')
    check('refusal_plus_operation_rejected', lambda d: d['trace'][3].update(event='click_input_refused', phase='resolveSelection'), 'reject')
    check('missing_up_no_UI', lambda d: d.update(trace=[r for r in d['trace'] if r['diagnosticSequence'] != 7]), 'pending')
    check('trace_prefix_incomplete_no_UI', lambda d: d.update(trace=d['trace'][1:]), 'pending')
    check('trace_gap_no_UI', lambda d: d.update(trace=[r for r in d['trace'] if r['diagnosticSequence'] != 4]), 'pending')
    check('duplicate_durable_operation', lambda d: d['operations'].append(d['operations'][0]), 'reject')
    check('different_operation_digest', lambda d: d['trace'][-1].update(operationIDDigest='f' * 64), 'reject')
    check('selection_tag_changed', lambda d: d['trace'][1].update(mouseProbeTag=2000), 'reject')
    check('selection_event_number_changed', lambda d: d['trace'][1].update(eventNumber=200), 'reject')
    check('sender_reservation_mismatch', lambda d: d['senders'][101].update(configurationSHA256='f' * 64), 'reject')
    check('wrong_binary', lambda d: d.update(binary='d' * 64), 'reject')
    check('wrong_attempt', lambda d: d.update(attempt='other-pair'), 'reject')
    check('intent_target_mismatch', lambda d: d['intents'][101].update(target='f' * 64), 'reject')
    check('intent_ordinal_mismatch', lambda d: d['intents'][102].update(ordinal=1), 'reject')
    check('session_changed', lambda d: d['trace'][-1].update(diagnosticSessionDigest='f' * 64), 'reject')
    check('extra_untagged_mouse', lambda d: d['trace'].append(dict(d['trace'][0], diagnosticSequence=9, mouseProbeTag=0)), 'reject')
    check('extra_selection', lambda d: d['trace'].append(dict(d['trace'][1], diagnosticSequence=9)), 'reject')
    check('duplicated_native_down', lambda d: d['trace'].append(dict(d['trace'][0], diagnosticSequence=9)), 'reject')
    check('duplicate_diagnostic_sequence', lambda d: d['trace'].append(dict(d['trace'][-1])), 'reject')
    # Actual runtime seeds are used by every identity fixture.
    assert early.order(1, {}, {}) == [0]; names.append('first_row_does_not_wait_for_second')
    assert early.order(2, {0: (101, 'a', 'b')}, {0: 5}) == [1, 0]; names.append('new_second_row_has_priority')
    assert early.order(2, {0: 1, 1: 1}, {0: 3, 1: 5}) == [0, 1]; names.append('fair_existing_rows')
    pre = {'ticketSHA256': 'a' * 64, 'cg': 1}
    known = {101: 'b' * 64, 102: 'c' * 64}
    def sample(seed, index, fid):
        return dict(ticketSHA256='a' * 64, cg=1, selectedRow=index, view='response',
                    payloadRecheckedAfterView=True, selectionProof='freshNativeClickAndOriginalPayloadBeforeAfter', selectedAttributeExposed=False, responseDisplayState='BOUNDED_ENTITY_TEXT', seed=seed,
                    filenameSHA256=known[seed], fileIDSHA256=fid)
    bindings = {}
    assert early.accept_sample(sample(102, 0, 'd' * 64), pre, {102: known[102]}, bindings, 0) == 102
    names.append('one_actual_operation_can_be_row_zero')
    bindings = {}
    assert early.accept_sample(sample(101, 0, 'd' * 64), pre, known, bindings, 0) == 101
    assert early.accept_sample(sample(102, 1, 'e' * 64), pre, known, bindings, 1) == 102
    names.append('two_original_rows_bind_independently')
    for label, altered, index, allowed in [
        ('row_file_id_changed', sample(101, 0, 'f' * 64), 0, known),
        ('row_duplicate_original', sample(101, 1, 'd' * 64), 1, known),
        ('old_selected_row_only_not_proof', {**sample(101, 0, 'd' * 64), 'selectionProof':'AXSelected'}, 0, known),
        ('missing_actual_selection_proof', {**sample(101, 0, 'd' * 64), 'selectionProof':None}, 0, known),
        ('post_view_identity_not_rechecked', {**sample(101, 0, 'd' * 64), 'payloadRecheckedAfterView': False}, 0, known),
        ('different_ticket', {**sample(101, 0, 'd' * 64), 'ticketSHA256': 'f' * 64}, 0, known),
        ('refused_seed_cannot_bind', sample(101, 0, 'd' * 64), 0, {102: known[102]}),
    ]:
        try:
            early.accept_sample(altered, pre, allowed, dict(bindings), index)
        except ValueError:
            pass
        else:
            raise AssertionError(label)
        names.append(label)
    # Public QA follow-up: all original 39 names/cases above remain in order.
    assert len(names) == 39
    def operation(data, index, value):
        asset, _ = data['operations'][index]
        data['operations'][index] = (asset, value)
        for row in data['trace']:
            if row.get('event') == 'attachment_entry_result' and row['assetIDDigest'] == digest_id(asset):
                row['operationIDDigest'] = digest_id(value)
    def shared_operation(data):
        operation(data, 1, data['operations'][0][1])
    check('two_assets_share_operation_matching_diagnostics', shared_operation,
          'reject', 'operation_uuid_reused')
    check('shared_operation_rejected_before_pending_sender',
          lambda d: [shared_operation(d), d['senders'].pop(102)],
          'reject', 'operation_uuid_reused')
    for label, transform in [
        ('operation_lowercase_alias', str.lower),
        ('operation_unhyphenated_alias', lambda s: s.replace('-', '')),
        ('operation_braced_alias', lambda s: '{' + s + '}'),
        ('operation_urn_alias', lambda s: 'urn:uuid:' + s),
        ('operation_trailing_newline', lambda s: s + '\n'),
        ('operation_leading_space', lambda s: ' ' + s),
        ('operation_path_suffix', lambda s: s + '/file.png'),
        ('operation_filename_suffix', lambda s: s + '.png'),
        ('operation_truncated', lambda s: s[:-1]),
    ]:
        check(label, lambda d, transform=transform: operation(d, 1, transform(d['operations'][1][1])), 'reject')
    check('shared_operation_lowercase_alias',
          lambda d: operation(d, 1, d['operations'][0][1].lower()),
          'reject', 'operation_uuid_not_canonical')
    check('foreign_operation_asset', lambda d: d['operations'].__setitem__(
          1, ('CCCCCCCC-0000-4000-8000-000000000001', d['operations'][1][1])),
          'reject', 'operation_conflict')
    def lowercase_asset(data):
        asset = next(iter(data['targets']))
        data['targets'][asset.lower()] = data['targets'].pop(asset)
    check('asset_lowercase_alias', lowercase_asset, 'reject', 'asset_uuid_not_canonical')
    check('operation_row_order_independent', lambda d: d['operations'].reverse())
    original = fixture(); result = classify(**original)
    wanted = {original['targets'][asset]: hashlib.sha256(('riftlet-' + op + '.png').encode()).hexdigest()
              for asset, op in original['operations']}
    assert {row['seed']: row['filenameSHA256'] for row in result['names']} == wanted
    assert len(set(wanted.values())) == 2
    names.append('distinct_canonical_operations_keep_distinct_exact_filenames')
    return {'PASS': True, 'offlineGateSchedulerAndIdentityCases': len(names),
            'retainedOriginalCases': 39, 'appendedCases': names[39:],
            'cases': names, 'GUIActions': 0, 'browserProcessesStarted': 0,
            'databaseAccesses': 0, 'HTTPRequests': 0}

if __name__ == '__main__':
    print(json.dumps(run(), sort_keys=True))
