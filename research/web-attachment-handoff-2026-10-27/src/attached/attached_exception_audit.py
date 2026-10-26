"""Offline diagnostic oracle for saved real exception traces; never controls a browser.
This is a lab evidence adapter, not the production adapter or strict internal READY.
"""
import json
from pathlib import Path


def classify(q, fixture, proof=None):
    def result(state, reason, **kw):
        return dict(state=state, reason=reason, strictREADY='NOT_PROVEN',
                    retainOriginal=True, automaticRetryAllowed=False, **kw)
    def unknown(reason):
        return result('UNKNOWN', reason)
    events=q.get('events', [])
    binding=q.get('binding', {})
    if not events or q.get('eventLimitReached'):
        return unknown('INCOMPLETE_TRACE')
    for i,e in enumerate(events):
        if e['sequence'] != i+1 or any(e.get(k)!=binding.get(k) for k in ['windowId','tabId','sessionId','documentNonce']):
            return unknown('EVENT_OR_TARGET_MISMATCH')
        if i and e['monotonicMs'] < events[i-1]['monotonicMs']:
            return unknown('EVENT_ORDER')
    if q.get('snapshot',{}).get('valid') is False or q.get('snapshot',{}).get('routeUnchanged') is False:
        return unknown('TARGET_INVALIDATED')
    name=fixture['name'];label=fixture['label']
    inputs=[e for e in events if e['event']=='file_entered' and e['state'].get('name')==name]
    if len(inputs)!=1 or inputs[0]['state']['bytes']!=fixture['bytes']:
        return unknown('INPUT_NOT_UNIQUE_OR_WRONG_SIZE')
    selected=inputs[0]['sequence']
    intents=[e for e in events if e['event']=='dispatch_intent' and e['state'].get('operationId')==fixture['operationId']]
    if len(intents)!=1 or intents[0]['sequence']>=selected:
        return unknown('OPERATION_NOT_UNIQUE')
    if not any(e['event']=='case_armed' and e['sequence']<selected for e in events):
        return unknown('NOT_ARMED')
    hashed=[e for e in events if e['event']=='input_hash' and e['state'].get('label')==label]
    if len(hashed)!=1 or hashed[0]['state']['sha256']!=fixture['sha256'] or hashed[0]['state']['bytes']!=fixture['bytes']:
        return unknown('INPUT_HASH_UNVERIFIED')
    if any(e['event']=='image_error' and e['state'].get('name')==name for e in events):
        return unknown('OWN_IMAGE_ERROR')
    if any(name in json.dumps(e,ensure_ascii=False) for e in q.get('uiErrors',[])):
        return unknown('ASSOCIATED_ERROR_VETO')
    card_id=image_id=editor_id=form_id=None
    started=hundred=ended=loaded=None
    snapshots=[(e,e['state'].get('snapshot',e['state'])) for e in events]
    snapshots.append(({'sequence':len(events)+1,'event':'tail','state':{}},q.get('snapshot',{})))
    for e,s in snapshots:
        if 'cards' not in s:continue
        if s.get('valid') is not True or s.get('routeUnchanged') is not True or s.get('documentNonce')!=binding.get('documentNonce'):
            return unknown('TARGET_INVALIDATED')
        editor_id=editor_id or s['editorNode']; form_id=form_id or s['formNode']
        if s['editorNode']!=editor_id or s['formNode']!=form_id:
            return unknown('COMPOSER_REPLACED')
        own=[c for c in s['cards'] if c['name']==name]
        if not own:
            if card_id:return unknown('OWN_ATTACHMENT_REMOVED')
            continue
        if len(own)!=1 or e['sequence']<=selected:
            return unknown('OWN_CARD_AMBIGUOUS_OR_PREEXISTING')
        c=own[0]; imgs=[n for n in c['nodes'] if n['tag']=='IMG']
        if len(imgs)!=1 or imgs[0]['attrs'].get('alt')!=name:
            return unknown('IMAGE_IDENTITY')
        im=imgs[0];card_id=card_id or c['cardNode']; image_id=image_id or im['nodeId']
        if c['cardNode']!=card_id or im['nodeId']!=image_id:
            return unknown('CARD_OR_IMAGE_REPLACED')
        ps=[n for n in c['nodes'] if n['attrs'].get('role')=='progressbar']
        if ps:
            if len(ps)!=1 or ps[0]['attrs'].get('aria-label')!='正在上传 '+name:
                return unknown('PROGRESS_NOT_OWNED')
            if ended:return unknown('UPLOAD_RESTARTED')
            started=started or e['sequence']
            if ps[0]['attrs'].get('aria-valuenow')=='100':hundred=hundred or e['sequence']
        elif hundred:
            ended=ended or e['sequence']
        if e['event']=='image_load' and e['state'].get('name')==name and ended and im['image'].get('complete') and im['image'].get('sourceKind')=='data' and im['image'].get('width',0)>0 and im['image'].get('height',0)>0:
            loaded=e['sequence']
        if e['event']=='tail':
            if ps:return result('UPLOADING','OWN_PROGRESS_PRESENT')
            if not im['image'].get('complete') or im['image'].get('sourceKind')!='data':
                return unknown('FINAL_PREVIEW_UNAVAILABLE')
    if not all([started,hundred,ended,loaded]):return unknown('INCOMPLETE_OWN_LIFECYCLE')
    if not proof or proof.get('name')!=name or not proof.get('sameCardAndSrc'):
        return unknown('CONTENT_UNVERIFIED')
    exact_bytes=(proof.get('targetStillValid') is True and proof.get('sha256')==fixture['sha256'] and proof.get('bytes')==fixture['bytes'] and proof.get('match') is True)
    source=proof.get('source',{});preview=proof.get('preview',{})
    exact_pixels=(proof.get('state')=='COMPLETE' and proof.get('targetValid') is True and proof.get('match') is True and source==preview and len(source.get('rgbaSha256',''))==64 and source.get('width',0)>0 and source.get('height',0)>0)
    if not (exact_bytes or exact_pixels):return unknown('CONTENT_MISMATCH')
    return result('ATTACHED','OWNED_UI_LIFECYCLE_AND_CONTENT',cardNode=card_id,imageNode=image_id,
                  contentIdentity='EXACT_BYTES' if exact_bytes else 'EXACT_DECODED_RGBA',
                  evidenceSequences={'input':selected,'uploading':started,'progress100':hundred,'progressEnded':ended,'finalImageLoad':loaded})


def run(root):
    root=Path(root);run=root/'evidence/exceptions/main'
    load=lambda name:json.loads((run/name).read_text())['result']
    cfg=json.loads((run/'config.json').read_text());fixtures={f['label']:f for f in cfg['fixtures']}
    identity=load('identity-observation.json');proofs={p['label']:p for p in load('concurrent-preview-proof.json')['receipts']}
    proofs['IDENTITY']=load('pixel-proof.json')
    queries={'IDENTITY':identity,'OTHER':identity,'MID':load('mid-final-before-bridge-refinement.json'),'POST100':load('post100-final.json')}
    switchlab=root/'evidence/exceptions/transition'
    fixtures['TAB_SWITCH']=json.loads((switchlab/'config.json').read_text())['fixtures'][0]
    queries['TAB_SWITCH']=json.loads((switchlab/'transition-final.json').read_text())['result']['query']
    verdicts={label:classify(q,fixtures[label],proofs.get(label)) for label,q in queries.items()}
    assert verdicts['IDENTITY']['state']==verdicts['OTHER']['state']=='ATTACHED'
    assert verdicts['IDENTITY']['cardNode']!=verdicts['OTHER']['cardNode']
    assert verdicts['MID']['state']==verdicts['POST100']['state']==verdicts['TAB_SWITCH']['state']=='UNKNOWN'
    assert verdicts['TAB_SWITCH']['reason']=='TARGET_INVALIDATED'
    prefix_results={}
    for label in ['MID','POST100']:
        q=queries[label];count=0
        for n in range(1,len(q['events'])+1):
            ev=q['events'][:n];snap=next((e['state'].get('snapshot',e['state']) for e in reversed(ev) if 'cards' in e['state'].get('snapshot',e['state'])),{})
            prefix={**q,'events':ev,'snapshot':snap,'uiErrors':[]}
            # A deliberately generous synthetic content proof tests the lifecycle veto.
            proof={'name':fixtures[label]['name'],'sameCardAndSrc':True,'targetStillValid':True,'match':True,'bytes':fixtures[label]['bytes'],'sha256':fixtures[label]['sha256']}
            assert classify(prefix,fixtures[label],proof)['state']!='ATTACHED'
            count+=1
        prefix_results[label]={'realTracePrefixes':count,'falseAttached':0,'proof':'SYNTHETIC_GENEROUS_PROOF_FOR_NEGATIVE_REPLAY_ONLY'}
    # Real concurrent trace: completion of OTHER cannot be borrowed by IDENTITY.
    other_load=verdicts['OTHER']['evidenceSequences']['finalImageLoad'];ev=identity['events'][:other_load]
    snap=ev[-1]['state'].get('snapshot',ev[-1]['state'])
    primary_when_other_done=classify({**identity,'events':ev,'snapshot':snap},fixtures['IDENTITY'],proofs['IDENTITY'])
    assert primary_when_other_done['state']!='ATTACHED'
    return {'kind':'OFFLINE_REPLAY_OF_REAL_TRACES_NOT_ADDITIONAL_LIVE_TESTS','verdicts':verdicts,
            'negativePrefixChecks':prefix_results,'primaryWhenOtherFinished':primary_when_other_done,
            'strictREADY':'NOT_PROVEN','scope':'Selected exception samples; not exhaustive reliability certification'}

if __name__=='__main__':
    import sys
    print(json.dumps(run(sys.argv[1]),ensure_ascii=False,indent=2))
