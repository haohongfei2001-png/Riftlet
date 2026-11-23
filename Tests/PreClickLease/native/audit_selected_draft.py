"""Audit two real file insertions bracketing an original, non-collapsed QA text selection."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import sqlite3

from rapid_timing import digest, one, require


TEXT='Riftlet QA: preserve this original draft while attaching images.'
PHRASE='preserve this original draft'
EXPECTED={'text':TEXT,'selectedText':PHRASE,'start':12,'end':40,'anchor':12,'focus':40,'direction':'forward'}


def audit(directory, profile):
    def read(name):
        return json.loads((directory/name).read_bytes())
    def native(name):
        x=read(name);raw=base64.b64decode(x['payloadBase64'],validate=True)
        require(hashlib.sha256(raw).hexdigest()==x['sha256'] and json.loads(raw)==x['payload'],'Invalid native scope digest')
        return x['payload']
    def counts(i):return {'fileInput':i,'fileChange':i,'sendButtonClicks':0,'formSubmit':0}

    child=read('child.json');package=child['candidate'];route=read('route.json')
    require(profile.resolve()==profile and (profile/'settings-review-identity.txt').read_text().strip()==child['profile'] and
            package['source']=='69b76cb025ab552b3480e3af095b627891874712' and
            package['sha256']=='666324176aadc4ffb9fd6fbfd0ca38772a169eb06394401f7abede374f7d3ee6','Candidate or QA profile mismatch')
    b=read('selection-before.json');base=b['baseline']
    prepage=read('page-before-2.json');postpage=read('page-after-2.json');last=read('final-page.json')
    pre=native('native-auth-press-2.json');initial=native('native-auth-press-1.json')
    for r in [pre,initial]:
        require(all(r.get(k) is True for k in ['originalSoleTab','exactTemporaryURL','originalSelection','systemForeground','dynamicSignature'])
                and r['page']['signedIn'] is True and r['page']['authSignals']['bootstrapStatus']=='logged_in' and
                (r['bundle'],r['sessionID'],r['windowID'],r['tabID'])==(route['applicationID'],route['session'],route['windowID'],route['tabID']),'Original authenticated scope changed')
    require(initial['page']['text']=='' and pre['page']['text']==TEXT and all(pre['page']['selection'][k]==v for k,v in EXPECTED.items() if k!='text') and
            initial['page']['timeOrigin']==pre['page']['timeOrigin']==base['timeOrigin'] and initial['page']['entryID']==pre['page']['entryID']==base['entryID'],'The nonempty original active selection was not observed before the click')
    for stamp in [base,read('selection-prepared.json'),prepage['nonemptySelectionSnapshot'],postpage['nonemptySelectionSnapshot'],last['nonemptySelectionSnapshot']]:
        require(all(stamp.get(k)==v for k,v in EXPECTED.items()) and all(stamp.get(k)==base[k] for k in ['entryID','timeOrigin','witnessEpoch'])
                and all(stamp.get(k) is True for k in ['original','activeOriginal','oldCardsIntact']) and stamp['priorCardCount']==1 and
                stamp['sendClicks']==stamp['formSubmits']==0 and stamp['textState']=='expected','Original native editor or DOM selection changed')
    require(len(TEXT)>0 and TEXT[12:40]==PHRASE and b['priorCounts']==prepage['counts']==counts(1) and postpage['counts']==last['counts']==counts(2)
            and len(prepage['files'])==1 and len(postpage['files'])==len(last['files'])==2 and prepage['files'][0] in postpage['files'] and
            all(r['rememberedCards']==1 and all(r.get(k) is True for k in ['originalDocument','originalEditor','allRememberedNodesPreserved','allRememberedCardsPresent','selectionUnchanged','textUnchanged']) for r in [prepage,postpage,last]),'Missing original cards or once-only input')
    actual_prep=[json.loads(line) for line in (directory/'selection-preparation-once.json').read_bytes().splitlines()]
    require([x['steps'] for x in actual_prep]==[['INSERT_INTENT'],['INSERT_INTENT','SELECT_INTENT'],['INSERT_INTENT','SELECT_INTENT','AX_RANGE_CONFIRMED']] and
        all(x['nativeRoute']==route and x['originalDraft']=={k:base[k] for k in ['entryID','timeOrigin','witnessEpoch']} for x in actual_prep),'Ambiguous editing or range setup')
    trace=[json.loads(l) for l in (directory/'candidate.stderr').read_bytes().splitlines() if l.startswith(b'{')]
    require(sum(e.get('event')=='selection_boundary' for e in trace)==2 and sum(e.get('event')=='native_bridge' and e.get('action')=='commit' for e in trace)==2,'Unexpected product input')
    source=[]
    with sqlite3.connect((profile/'queue.sqlite').as_uri()+'?mode=ro',uri=True) as db:
        db.execute('begin')
        require(db.execute('pragma quick_check').fetchall()==[('ok',)] and all(db.execute('select count(*) from '+t).fetchone()[0]==2 for t in ['assets','operations','upload_starts']),'Unverified isolated database')
        for i in [1,2]:
            p,=read(f'positive-{i}.json');click=read(f'click-{i}.json');capture=read(f'capture-{i}.json')
            op=p['operationID']
            asset,tar=db.execute('select asset_id,target_json from operations where id=?',(op,)).fetchone()
            target=json.loads(tar)
            require((target['applicationID'],target['sessionID'],target['windowID'],target['tabID'])==(route['applicationID'],route['session'],route['windowID'],route['tabID']),'Operation target changed')
            (s,started_at),=db.execute('select receipt_json,started_at from upload_starts where operation_id=?',(op,)).fetchall()
            start=json.loads(s);ack=start['attachmentAcceptanceEvidence']
            v,=db.execute('select value from checkpoints where key=?',('transfer-dispatch-call-v1:'+op,)).fetchone()
            inv=json.loads(base64.b64decode(v,validate=True))
            (asset_image,active,visibility),=db.execute('select image_json,active_operation_id,visibility from assets where id=?',(asset,)).fetchall()
            require(active==op and visibility=='swallowed' and start['target']==inv['target']==target and
                    op==start['operationID']==inv['operationID'] and asset==start['assetID']==inv['assetID']==click['assetID'] and
                    inv['invocationID']==p['invocationID'] and inv['inputExecutionReturned'] and ack['signal']=='attachmentAccepted' and
                    ack['inputCount']==1 and ack['evidenceID']==p['evidenceID'] and start['belongsToOriginalDraft'] and
                    start['outcome']=='uploadStarted' and not start['hasError'] and not start['safeToRetry'] and start['attachmentID']==p['cardID'] and started_at,'No exact durable START')
            name=capture['fileName'];original=profile/'capture-source'/name;media=profile/'media'/(asset.lower()+'.png')
            require(original.resolve()==original and media.resolve()==media and original.read_bytes()==media.read_bytes() and original.read_bytes().startswith(b'\x89PNG\r\n\x1a\n') and
                hashlib.sha256(original.read_bytes()).hexdigest()==p['sha256']==json.loads(asset_image)['sha256']==start['assetSHA256']==inv['assetSHA256']==capture['sha256'] and
                capture['systemScreenshotMarker'] is True and capture['ownerVerified'] is True,'Original PNG changed')
            r=[e for e in postpage['observedInputReceipts'] if e['knownQAFileName'].lower()==p['inputName'].lower()]
            px=[e for e in postpage['pixelEvidence'] if e['forLastInput'].lower()==p['inputName'].lower()]
            pics=[c for c in postpage['files'] if c['qaFile'].lower() in [p['inputName'].lower(),p['inputName'][:-4].lower()+'.webp']]
            require([e['event'] for e in r]==['input','change'] and all(e['sha256']==p['sha256'] and e['sameInputAsOriginal'] for e in r) and
                    len(pics)==len(px)==1 and pics[0]['decoded'] and px[0]['file']==px[0]['decoded'] and px[0]['decoded']['digest']==p['pixelsSHA256'],'Unverified original file receipt or attachment pixels')
            down=one(trace,event='selection_boundary',source='mouse',eventNumber=click['eventNumber'],assetIDDigest=digest(asset))['eventUptime']
            one(trace,event='preclick_lease',phase='frozen',requestIDDigest=p['requestDigest'],originalEventUptime=down)
            one(trace,event='preclick_lease',phase='consumed',requestIDDigest=p['requestDigest'],operationIDDigest=digest(op))
            one(trace,event='attachment_entry_result',phase='uploadStarted',operationIDDigest=digest(op),startObserved=True)
            require(click['delivery']=='MOUSE_DOWN_ACKNOWLEDGED' and down==p['downUptime'] and p['ackUptime']<down and digest(target['clickBindingID'])==p['requestDigest'],'Missing original native ACK')
            source.append({'target':target,'record':p,'down':down})
    a,z=source
    for k in ['sha256','invocationID','operationID','cardID','requestDigest','pixelsSHA256','evidenceID']:
        require(a['record'][k]!=z['record'][k],'Duplicate target '+k)
    pending=read('new-source-and-prepared-target.json')
    require(pre['systemUptime']<z['down'] and
            pending==b['pending'] and pending['assetSHA256']==z['record']['sha256'] and pending['bindingSHA256']==z['record']['requestDigest'],'No earlier original selection and matched new input')
    k=('documentID','composerID','draftGeneration')
    require(all(a['target'][f]==z['target'][f] and z['target'][f] for f in k) and read('db-1.json')['operations'][0]['originalDraftGeneration']==b['productEpochFromOriginalSeedBeforeNewInput']==z['target']['draftGeneration'],'Product source draft or generation changed')
    require(pre['page'].get('draftEpoch') is None and b['productEpochFromPendingSlotBeforeNewInput'] is None and pending['draftEpoch'] is None,'Different direct epoch evidence than this audited series')
    return {'family':pre['family'],'candidate':package,'textAndSelection':'PASS','textLength':len(TEXT),'textSHA256':hashlib.sha256(TEXT.encode()).hexdigest(),
            'selectedText':PHRASE,'selectionUTF16':{'start':12,'end':40,'anchor':12,'focus':40,'direction':'forward'},
            'originalEditorAndEndpointNodesPreserved':True,'oldAttachmentNodePreserved':True,'originalProductDraftEpoch':{
              'sampleSourceBeforeNewInput':'already accepted seed, original SQLite operation','seedAndNewCommittedEpochEqual':True,
              'matchingCommittedEpochSHA256':digest(z['target']['draftGeneration']),'currentPendingSlotDirectlySampledBeforeClick':False},
            'nativePendingACKMatchedConsumedBinding':True,'beforeCounts':counts(1),'afterCounts':counts(2),
            'inputs':[{'pngSHA256':x['record']['sha256'],'decodedWebsitePixelSHA256':x['record']['pixelsSHA256'],'operationIDDigest':digest(x['record']['operationID']),'invocationIDDigest':digest(x['record']['invocationID']),'startEvidenceIDDigest':digest(x['record']['evidenceID'])} for x in source],
            'rawSHA256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(directory.iterdir()) if p.suffix=='.json' or p.name=='candidate.stderr'}}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('directory',type=Path);parser.add_argument('profile',type=Path);args=parser.parse_args()
    print(json.dumps(audit(args.directory,args.profile),indent=2,sort_keys=True,allow_nan=False))
