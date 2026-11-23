"""Audit a seed and three native pairs against the original website receipts, PNGs and SQLite."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import sqlite3

from rapid_timing import analyze, digest, one, require


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(directory, profile):
    def read(name):
        return json.loads((directory/name).read_bytes())
    hashes = {p.name: file_hash(p) for p in sorted(directory.glob('*.json'))}
    hashes['signed-app.stderr'] = file_hash(directory/'candidate.stderr')
    child=read('child.json')
    candidate=child['candidate']
    require(candidate['source']=='69b76cb025ab552b3480e3af095b627891874712' and
            candidate['sha256']=='666324176aadc4ffb9fd6fbfd0ca38772a169eb06394401f7abede374f7d3ee6' and
            profile.resolve()==profile and (profile/'settings-review-identity.txt').read_text().strip()==child['profile'], 'Wrong candidate or profile')
    route=read('route.json')
    original_entry=None
    for label in ['native-auth-startup','native-auth-press-1','native-auth-press-2','native-auth-press-4','native-auth-press-6']:
        e=read(label+'.json')
        blob=base64.b64decode(e['payloadBase64'],validate=True)
        r=e['payload'];p=r['page']
        require(hashlib.sha256(blob).hexdigest()==e['sha256'] and json.loads(blob)==r and
                (r['bundle'],r['sessionID'],r['windowID'],r['tabID'])==(route['applicationID'],route['session'],route['windowID'],route['tabID']) and
                all(r.get(k) is True for k in ['originalSoleTab','originalSelection','systemForeground','dynamicSignature','exactTemporaryURL']) and
                all(p.get(k) is True for k in ['editor','signedIn','uploadEntry']) and p['authSignals']['bootstrapStatus']=='logged_in',
                'Unverified original authenticated Temporary Chat')
        current=(r['pid'],p['entryID'],p['timeOrigin'])
        require(original_entry is None or original_entry==current,'Native document replaced')
        original_entry=current
    trace=[json.loads(line) for line in (directory/'candidate.stderr').read_bytes().splitlines() if line.startswith(b'{')]
    final=read('final-page.json')
    require(final['counts']=={'fileInput':7,'fileChange':7,'formSubmit':0,'sendButtonClicks':0} and
            final['originalDocument'] and final['originalEditor'] and len(final['files'])==7 and final['allRememberedCardsPresent'] and
            final['allRememberedNodesPreserved'], 'Unexpected final website state')
    accepted=sum((read(f'positive-{n}.json') for n in [1,3,5,7]), [])
    require([x['index'] for x in accepted]==list(range(1,8)),'Unexpected accepted series')
    for key in ['sha256','pixelsSHA256','requestDigest','eventNumber','operationID','invocationID','evidenceID','cardID']:
        require(len({x[key] for x in accepted})==7,'Duplicate '+key)
    require(len([x for x in trace if x.get('event')=='selection_boundary'])==7,'Unexpected native press')
    require(len([x for x in trace if x.get('event')=='native_bridge' and x.get('action')=='commit'])==7,'Unexpected native commit')
    profile_db=profile/'queue.sqlite'
    db=sqlite3.connect(profile_db.as_uri()+'?mode=ro',uri=True)
    uniqueness=[]
    target_ids=set()
    try:
        db.execute('begin')
        require(db.execute('pragma quick_check').fetchall()==[('ok',)],'SQLite integrity check failed')
        total={table:db.execute('select count(*) from '+table).fetchone()[0] for table in ['operations','upload_starts','assets']}
        require(total['operations']==total['upload_starts']==7 and total['assets'] in (7,8),'Unexpected durable operation count')
        for p in accepted:
            n=p['index'];opid=p['operationID']
            capture=read(f'capture-{n}.json');click=read(f'click-{n}.json')
            asset, target_json=db.execute('select asset_id,target_json from operations where id=?',(opid,)).fetchone()
            target=json.loads(target_json)
            (asset_id,image_json,status,visibility,active),=db.execute('select id,image_json,status,visibility,active_operation_id from assets where id=?',(asset,)).fetchall()
            (start_json,started_at),=db.execute('select receipt_json,started_at from upload_starts where operation_id=?',(opid,)).fetchall()
            (dispatch,),=db.execute('select value from checkpoints where key=?',('transfer-dispatch-call-v1:'+opid,)).fetchall()
            start=json.loads(start_json);c=json.loads(base64.b64decode(dispatch,validate=True));proof=start['attachmentAcceptanceEvidence']
            image=json.loads(image_json);source=profile/'capture-source'/capture['fileName'];media=profile/'media'/(asset.lower()+'.png')
            require(capture['systemScreenshotMarker'] and capture['ownerVerified'] and capture['browserStillForeground'] and
                    source.resolve()==source and media.resolve()==media and source.read_bytes()[:8]==b'\x89PNG\r\n\x1a\n' and
                    file_hash(source)==file_hash(media)==capture['sha256']==p['sha256']==image['sha256']==start['assetSHA256']==c['assetSHA256'],'Original PNG mismatch')
            require(started_at>0 and visibility=='swallowed' and active==opid and asset_id==start['assetID']==c['assetID']==click['assetID'] and
                    start['target']==c['target']==target and c['operationID']==start['operationID']==opid and c['invocationID']==p['invocationID'] and
                    c['inputExecutionReturned'] is True and start['outcome']=='uploadStarted' and start['belongsToOriginalDraft'] is True and
                    start['hasError'] is False and start['safeToRetry'] is False and start['attachmentID']==p['cardID'] and
                    proof['inputCount']==1 and proof['signal']=='attachmentAccepted' and proof['evidenceID']==p['evidenceID'] and
                    digest(target['clickBindingID'])==p['requestDigest'], 'START or dispatch mismatch')
            require((target['sessionID'],target['windowID'],target['tabID'],target['applicationID'])==
                    (route['session'],route['windowID'],route['tabID'],route['applicationID']),'Original route changed')
            target_ids.add((target['documentID'],target['composerID']))
            inputs=[v for v in final['observedInputReceipts'] if v['knownQAFileName'].lower()==p['inputName'].lower()]
            pics=[v for v in final['files'] if v['qaFile'].lower() in [p['inputName'].lower(),p['inputName'][:-4].lower()+'.webp']]
            px=[v for v in final['pixelEvidence'] if v['forLastInput'].lower()==p['inputName'].lower()]
            require([v['event'] for v in inputs]==['input','change'] and all(v['sha256']==p['sha256'] and v['bytes']==source.stat().st_size and v['sameInputAsOriginal'] for v in inputs) and
                    len(pics)==len(px)==1 and pics[0]['decoded'] and px[0]['file'] and px[0]['file']==px[0]['decoded'] and px[0]['decoded']['digest']==p['pixelsSHA256'], 'Real input or preview pixels mismatch')
            mouse=one(trace,event='selection_boundary',source='mouse',eventNumber=click['eventNumber'],assetIDDigest=digest(asset))
            freeze=one(trace,event='preclick_lease',phase='frozen',requestIDDigest=p['requestDigest'],originalEventUptime=mouse['eventUptime'])
            ack=one(trace,event='preclick_lease',phase='armed',requestIDDigest=p['requestDigest'])
            one(trace,event='preclick_lease',phase='consumed',requestIDDigest=p['requestDigest'],operationIDDigest=digest(opid))
            one(trace,event='attachment_entry_result',phase='uploadStarted',operationIDDigest=digest(opid),startObserved=True)
            require(mouse['eventUptime']==click['eventUptime']==p['downUptime'] and
                    ack['acknowledgedUptime']==freeze['acknowledgedUptime']==p['ackUptime']<mouse['eventUptime'],'Incomplete original native lease')
            uniqueness.append({'photo':n,'pngSHA256':p['sha256'],'webDecodedPixelsSHA256':p['pixelsSHA256'],'operationIDDigest':digest(opid),
                               'invocationIDDigest':digest(c['invocationID']),'durableStartEvidenceIDDigest':digest(proof['evidenceID'])})
        require(len(target_ids)==1,'Series changed original document or composer')
        if total['assets']==8:
            extra,=db.execute("select status,active_operation_id from assets where id not in (select asset_id from operations)").fetchall()
            require(extra==('pending',None),'Unexpected eighth capture activity')
    finally:
        db.close()
    manifests={'originalRawSHA256':hashes,'dmgSHA256':candidate['sha256'],'productCommit':candidate['source'],'family':'chrome' if route['applicationID']=='com.google.Chrome' else 'edge'}
    pairs=[]
    for n in [2,4,6]:
        first=accepted[n-1]['downUptime']
        times=analyze(manifests,directory,n+1)
        pre=read(f'preclick-pair-{n}.json')
        native=read(f'pair-native-{n}.json')
        sender=read(f'sender-elapsed-{n}.json')
        before=read(f'cards-before-{n}.json');after=read(f'page-after-{n+1}.json')
        require(native['exit']==0 and len(native['results'])==2 and all(r['eventsPosted']==2 and r['originalDraftVerified'] and r['geometryVerified'] for r in native['results']), 'Native sender mismatch')
        original,=target_ids
        require(pre['sourceDocumentAndEditor']==dict(zip(['documentID','composerID'],original)) and len(pre['bindings'])==2
                and {row['bindingDigest'] for row in pre['bindings']}=={p['requestDigest'] for p in accepted[n-1:n+1]} and
                max(row['acknowledgedUptime'] for row in pre['bindings'])<=pre['sampleUptime']<first,'Two original pre-click signed ACKs missing')
        ids=[x['operationID'].lower() for x in accepted[:n-1]]
        require(before['rememberedCards']==after['rememberedCards']==len(ids) and all(after[k] for k in ['allRememberedNodesPreserved','allRememberedCardsPresent','previousQAImagesPresent']) and
                {i['qaFile'][8:].rsplit('.',1)[0].lower() for i in before['files']}==set(ids),'Existing cards changed')
        clocks=times['events']
        ms=lambda t:round((t-first)*1000,3)
        for j,row in enumerate(clocks):
            row.pop('operationID');row.pop('qaLastPreDispatchRowSampleMS')
            # The sampleUptime is an earlier non-posting row check; verifierHostUptime is just before down/up posting.
            bound=native['results'][j]
            row['qaFinalCheckCompletedAndPostingBeganMS']=ms(bound['verifierHostUptime'])
            row['qaFinalCheckStartedMS']=ms(bound['verifierHostUptime']-bound['finalCheckMS']/1000)
        delta=times['downDeltaMS']
        arrivals=[one(trace,event='selection_boundary',source='mouse',eventNumber=p['eventNumber'])['callbackUptime'] for p in accepted[n-1:n+1]]
        callback=round((arrivals[1]-arrivals[0])*1000,3)
        require(0<delta<2000 and 0<callback<2000 and all(x['preclickAcknowledgedMS']<0 for x in clocks),'Pair was not rapid or prebound')
        pairs.append({'indices':[n,n+1],'originalMouseDownDeltaMS':delta,'callbackArrivalDeltaMS':callback,'previousCardsPreserved':len(ids),
                      'verifierAdmissionIntervalMS':[ms(pre['verifierPreparationStartedUptime']),ms(pre['verifierPreparationFinishedUptime'])],
                      'verifierSenderIntervalMS':[ms(sender['enteredUptime']),ms(sender['returnedUptime'])],
                      'verifierBetweenPostsBeforeSecondFinalCheckMS':round(clocks[1]['qaFinalCheckStartedMS']-clocks[0]['qaFinalCheckCompletedAndPostingBeganMS'],3),
                      'documentEpochDirectlyReadBeforePair':pre['activeDraftEpochBefore'] is not None,'bothOriginalOperationsShareDraftEpoch':True,'events':clocks})
    return {'family':manifests['family'],'status':'RAPID_PAIRS_PASS','candidate':candidate,'pairs':pairs,'sqliteCounts':total,
            'sevenIndependentInputsAndStarts':uniqueness,'finalWebsiteCounts':final['counts'],
            'originalRawReceiptSHA256':hashes}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path);parser.add_argument('profile',type=Path)
    args=parser.parse_args()
    print(json.dumps(audit(args.directory,args.profile),indent=2,sort_keys=True,allow_nan=False))
