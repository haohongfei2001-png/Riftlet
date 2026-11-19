"""Pure validation of an already-observed same-file UI projection; performs no observation."""
import re
SHA = re.compile(r'[a-f0-9]{64}\Z')
def need(ok, why):
    if not ok:
        raise ValueError(why)

def order(count, visited, times):
    need(type(count) is int and 0 <= count <= 2, 'ambiguous_new_processing_rows')
    return sorted(range(count), key=lambda x:(x in visited, times.get(x,0)))

def accept_sample(result, pre, known, bindings, index):
    need(result.get('ticketSHA256') == pre['ticketSHA256'] and result.get('cg') == pre['cg'], 'original_native_context_changed')
    need(result.get('selectedRow') == index and result.get('view') == 'response' and result.get('payloadRecheckedAfterView') is True and result.get('selectionProof') == 'freshNativeClickAndOriginalPayloadBeforeAfter' and type(result.get('selectedAttributeExposed')) is bool and result.get('responseDisplayState') in {'BOUNDED_ENTITY_TEXT','NO_ENTITY_TEXT_EXPOSED','AMBIGUOUS_ENTITY_TEXT'}, 'original_row_not_rebound')
    seed = result.get('seed')
    need(seed in known and result.get('filenameSHA256') == known[seed] and SHA.fullmatch(result.get('fileIDSHA256','')) is not None, 'original_file_identity_mismatch')
    identity = (seed,result['filenameSHA256'],result['fileIDSHA256'])
    if index in bindings:
        need(bindings[index] == identity, 'original_row_identity_changed')
    need(not any(i != index and (b[0] == seed or b[2] == identity[2]) for i,b in bindings.items()), 'two_rows_reuse_one_original_file')
    bindings[index] = identity
    return seed
