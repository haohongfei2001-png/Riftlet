"""Pure QA scheduling gate. It grants neither product input nor service success."""
import hashlib
import re
import uuid

HASH = re.compile(r'[a-f0-9]{64}\Z')
IDENTITY = ('assetIDDigest', 'attemptID', 'configurationSHA256',
            'diagnosticSessionDigest', 'eventNumber', 'mouseProbeTag',
            'productBinarySHA256', 'afterDiagnosticSequence')

def need(value, reason):
    if not value:
        raise ValueError(reason)

def digest_id(value):
    return hashlib.sha256(value.lower().encode()).hexdigest()

def classify(targets, operations, trace, senders, reservations, intents,
             attempt, binary, *, allowed_seeds):
    """None means still pending; errors stop. All inputs are original bounded data.

    Only resolveSelection + no durable operation + no entered setter is accepted
    as a pre-input refusal. submitSelection/UNKNOWN never takes that shortcut.
    Every target needs one exact tagged down/up/selection and its reservation.
    """
    SEEDS = set(allowed_seeds)
    need(len(SEEDS) == 2 and len(targets) == 2 and set(targets.values()) == SEEDS, 'wrong_pair_targets')
    for asset in targets:
        need(str(uuid.UUID(asset)).upper() == asset, 'asset_uuid_not_canonical')
    need(len(operations) <= 2 and len({a for a, _ in operations}) == len(operations)
         and all(a in targets for a, _ in operations), 'operation_conflict')
    ops = dict(operations)
    for op in ops.values():
        need(str(uuid.UUID(op)).upper() == op, 'operation_uuid_not_canonical')
    if any(seed not in senders or seed not in reservations or seed not in intents
           for seed in SEEDS):
        return None
    by_hash = {digest_id(asset): (asset, seed) for asset, seed in targets.items()}
    sessions, tags, numbers, boundaries = set(), set(), set(), []
    for seed in sorted(SEEDS):
        sender, reservation, intent = senders[seed], reservations[seed], intents[seed]
        need(all(k in sender and sender[k] == reservation.get(k) for k in IDENTITY),
             'sender_reservation_identity_mismatch')
        need(reservation.get('status') == 'reservedBeforePost', 'reservation_not_original')
        need(sender['attemptID'] == attempt and sender['productBinarySHA256'] == binary,
             'sender_attempt_or_product_changed')
        key = sender['assetIDDigest']
        need(key in by_hash and by_hash[key][1] == seed and intent.get('target') == key
             and intent.get('ordinal') == sorted(SEEDS).index(seed) + 1,
             'sender_target_or_ordinal_changed')
        need(HASH.fullmatch(sender['diagnosticSessionDigest']) is not None
             and HASH.fullmatch(sender['configurationSHA256']) is not None,
             'sender_digest_invalid')
        for key in ['mouseProbeTag', 'eventNumber', 'afterDiagnosticSequence']:
            need(type(sender[key]) is int and sender[key] >= 0, 'sender_native_number_invalid')
        need(sender['mouseProbeTag'] > 0, 'sender_tag_required')
        sessions.add(sender['diagnosticSessionDigest']); tags.add(sender['mouseProbeTag'])
        numbers.add(sender['eventNumber']); boundaries.append(sender['afterDiagnosticSequence'])
    need(len(sessions) == 1 and len(tags) == len(numbers) == 2, 'sender_pair_identity_conflict')
    session = next(iter(sessions)); first = min(boundaries)
    relevant = [r for r in trace if type(r.get('diagnosticSequence')) is int
                and r['diagnosticSequence'] > first]
    need(all(r.get('diagnosticSessionDigest') == session for r in relevant),
         'diagnostic_session_changed')
    seqs = [r['diagnosticSequence'] for r in relevant]
    need(seqs == sorted(set(seqs)), 'diagnostic_sequence_conflict')
    if not seqs or seqs != list(range(first + 1, seqs[-1] + 1)):
        return None  # No GUI over a trace prefix or gap that could hide another click.
    selections = [r for r in relevant if r.get('event') == 'selection_boundary']
    need(len(selections) <= 2 and all(r.get('assetIDDigest') in by_hash for r in selections),
         'extra_or_foreign_selection')
    mouse = [r for r in relevant if r.get('event') == 'mouse_application_event']
    need(all(r.get('mouseProbeTag') in tags for r in mouse), 'unowned_mouse_event')
    states, names = [], []
    for asset, seed in sorted(targets.items(), key=lambda x: x[1]):
        sender = senders[seed]; key = digest_id(asset)
        mine = [r for r in selections if r.get('assetIDDigest') == key]
        need(len(mine) <= 1, 'duplicate_original_selection')
        if not mine:
            return None
        selection = mine[0]
        need(selection.get('mouseProbeTag') == sender['mouseProbeTag']
             and selection.get('eventNumber') == sender['eventNumber']
             and selection['diagnosticSequence'] > sender['afterDiagnosticSequence'],
             'selection_sender_mismatch')
        posted = [r for r in mouse if r.get('mouseProbeTag') == sender['mouseProbeTag']]
        need(len(posted) <= 2 and all(r.get('eventNumber') == sender['eventNumber']
             and r['diagnosticSequence'] > sender['afterDiagnosticSequence'] for r in posted),
             'mouse_pair_identity_mismatch')
        phases = [r.get('phase') for r in posted]
        need(all(p in ['down', 'up'] for p in phases) and len(set(phases)) == len(phases),
             'mouse_pair_duplicate_or_invalid')
        if phases != ['down', 'up']:
            return None
        need(posted[0]['diagnosticSequence'] < selection['diagnosticSequence']
             < posted[1]['diagnosticSequence'], 'selection_outside_original_mouse_pair')
        own = [r for r in relevant if r.get('assetIDDigest') == key
               and r['diagnosticSequence'] > selection['diagnosticSequence']]
        refusals = [r for r in own if r.get('event') == 'click_input_refused']
        entries = [r for r in own if r.get('event') == 'attachment_entry_result']
        need(len(refusals) <= 1, 'duplicate_refusal')
        op = ops.get(asset)
        if refusals:
            need(op is None and not any(r.get('setterEntered') is True for r in entries),
                 'refusal_conflicts_with_operation_or_input')
            if refusals[0].get('phase') != 'resolveSelection':
                return None
            states.append({'seed': seed, 'state': 'EXPLICIT_PREINPUT_REFUSAL',
                           'phase': 'resolveSelection', 'durableOperationCount': 0})
            continue
        if op is None:
            return None
        op_hash = digest_id(op)
        need(all(r.get('operationIDDigest') == op_hash for r in entries),
             'diagnostic_operation_mismatch')
        if not any(r.get('setterEntered') is True and r.get('changeReturned') is True
                   for r in entries):
            return None
        states.append({'seed': seed, 'state': 'ORIGINAL_CHANGE_RETURNED',
                       'durableOperationCount': 1})
        names.append({'seed': seed, 'filenameSHA256': hashlib.sha256(
            ('riftlet-' + op + '.png').encode()).hexdigest()})
    return {'states': states, 'names': names, 'bothOriginalAttemptsSettled': True,
            'observedOperationCount': len(names), 'takeNativeUI': bool(names),
            'newInputOrRetryAuthorized': False}
