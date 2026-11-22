"""Build 59 private independent selection witness. Only run after seed START and draft-mark."""
import base64
import hashlib
from prepare import prepare
import json
import os
import subprocess
import uuid
from pathlib import Path

TEXT='Riftlet QA: preserve this original draft while attaching images.'
PHRASE='preserve this original draft'
readonlyKeys=('entryID','timeOrigin','witnessEpoch','text','selectedText','start','end','anchor','focus','direction','priorCardCount')

def require(ok,reason):
    if not ok: raise RuntimeError(reason)

def accepted(row):
    return row.get('startMatchesOriginal') is True and row.get('startCount')==1 and row.get('startSignal')=='attachmentAccepted' and all(
        isinstance(row.get(k),str) and bool(row[k]) for k in ('id','assetID','invocationID','uniqueStartEvidence','currentAttachmentID','originalDocumentID','originalComposerID','originalDraftGeneration'))

class SelectionStep:
    def __init__(self,state_dir,out_dir,route,seed_op,native_watch,helpers):
        self.helpers = Path(helpers).resolve()
        require(accepted(seed_op),'SEED_ORIGINAL_START_REQUIRED')
        self.state=Path(state_dir); self.out=Path(out_dir); self.route=dict(route)
        self.seed=dict(seed_op); self.watch=native_watch; self.before=None
        self.claim={'documentID':seed_op['originalDocumentID'],'composerID':seed_op['originalComposerID'],
                    'operation':seed_op['id'],'invocation':seed_op['invocationID'],'evidence':seed_op['uniqueStartEvidence'],
                    'nonce':str(uuid.uuid4())}

    def probe(self,mode):
        env={**os.environ,'RIFTLET_SELECTION_CLAIM':json.dumps({**self.claim,'mode':mode})}
        p=subprocess.run([self.helpers/'selection-observer',self.state],capture_output=True,timeout=12,env=env)
        require(p.returncode==0,p.stderr.decode('utf-8','replace')[:180].strip() or 'ORIGINAL_SELECTION_OBSERVER_UNAVAILABLE')
        wrapped=json.loads(p.stdout);data=base64.b64decode(wrapped['payloadBase64'],validate=True)
        require(hashlib.sha256(data).hexdigest()==wrapped['sha256'],'SELECTION_RECEIPT_DIGEST_MISMATCH')
        native=json.loads(data)
        require(native==wrapped['payload'] and native['bundle']==self.route['applicationID'] and native['sessionID']==self.route['session'] and
                all(native[k]==self.route[k] for k in ('windowID','tabID')) and all(native[k] is True for k in
                ('dynamicSignature','exactTemporaryURL','originalSelection','originalSoleTab','systemForeground')), 'ORIGINAL_NATIVE_ROUTE_LOST')
        page=native['page']; s=page['selectionProbe']
        require(page['signedIn'] and s['entryID']==page['entryID'] and s['timeOrigin']==page['timeOrigin'] and s['original'] and
                s['oldCardsIntact'] and s['sendClicks']==s['formSubmits']==0,'ORIGINAL_PAGE_OR_PRIOR_CARD_UNVERIFIED')
        return native,s

    def save(self,name,value):
        with (self.out/name).open('x') as f:
            os.fchmod(f.fileno(),0o600); json.dump(value,f,indent=2);f.write('\n')

    def prepare(self,pending):
        require(isinstance(pending,dict) and all(isinstance(pending.get(k),str) and len(pending[k])==64 and
                all(c in '0123456789abcdef' for c in pending[k]) for k in ('bindingSHA256','assetSHA256')),'NEW_PREACK_AND_FILE_REQUIRED')
        for key in ('documentID','composerID'):
            require(not pending.get(key) or pending[key]==self.claim[key],'PENDING_ORIGINAL_TARGET_MISMATCH')
        self.pending=dict(pending)
        self.claim.update(pendingFile=self.pending['assetSHA256'])
        old=self.watch()
        require(old['originalDocument'] and old['originalEditor'] and old['allRememberedCardsPresent'] and old['allRememberedNodesPreserved']
                and old['rememberedCards']>=1 and old['counts']['formSubmit']==old['counts']['sendButtonClicks']==0,'MARKED_OLD_CARDS_REQUIRED')
        self.old_files=sorted(r['qaFile'].lower() for r in old['files'])
        require(len(self.old_files)==len(set(self.old_files))==old['rememberedCards'] and all(r['decoded'] for r in old['files']),'UNIQUE_BASELINE_CARDS_REQUIRED')
        self.old_counts=dict(old['counts'])
        init,s=self.probe('init')
        require(s['textState']=='empty' and s['priorCardCount']==len(self.old_files),'EMPTY_BOUND_ORIGINAL_EDITOR_REQUIRED')
        result=prepare(self.route,lambda:self.probe('state')[0],lambda:self.probe('state')[1],self.out,self.helpers/'ax_prepare')
        _,base=self.probe('before')
        require(base['text']==TEXT and base['selectedText']==PHRASE and (base['start'],base['end'])==(12,40) and
                (base['direction'],base['anchor'],base['focus']) in (('forward',12,40),('backward',40,12)),'REAL_DIRECTED_SELECTION_REQUIRED')
        self.before=base
        self.save('selection-before.json',{'baseline':base,
                  'productEpochFromOriginalSeedBeforeNewInput':self.seed['originalDraftGeneration'],
                  'productEpochFromPendingSlotBeforeNewInput':self.pending.get('draftEpoch'),
                  'pending':self.pending,'native':result,'priorFiles':self.old_files,'priorCounts':self.old_counts})
        return base

    def read_page(self):
        require(self.before is not None,'SELECTION_BEFORE_MISSING')
        page=self.watch(); _,now=self.probe('after')
        require(all(now[k]==self.before[k] for k in readonlyKeys),'SELECTION_OR_DRAFT_CHANGED')
        # Replace just the original empty-draft baseline for these two fields.
        return {**page,'priorEmptyTextUnchanged':page['textUnchanged'],'priorEmptySelectionUnchanged':page['selectionUnchanged'],
                'textUnchanged':now['text']==self.before['text'],'selectionUnchanged':all(now[k]==self.before[k] for k in ('anchor','focus','start','end','direction','selectedText')),
                'nonemptySelectionSnapshot':now}

    def finish(self,new_op):
        require(accepted(new_op) and all(new_op[k]!=self.seed[k] for k in ('id','assetID','invocationID','uniqueStartEvidence','currentAttachmentID')),
                'NEW_DISTINCT_ORIGINAL_START_REQUIRED')
        page=self.read_page(); after=page['nonemptySelectionSnapshot']
        require(hashlib.sha256(str(uuid.UUID(new_op['clickBindingID'])).encode()).hexdigest()==self.pending['bindingSHA256'],
                'NEW_OPERATION_DID_NOT_CONSUME_PREPARED_BINDING')
        require((new_op['originalDocumentID'],new_op['originalComposerID'])==
                (self.seed['originalDocumentID'],self.seed['originalComposerID']),'NEW_OPERATION_DRAFT_MISMATCH')
        pre_epoch=self.pending.get('draftEpoch')
        require(not pre_epoch or pre_epoch==new_op['originalDraftGeneration'],'NEW_OPERATION_PRECLICK_DRAFT_EPOCH_MISMATCH')
        active=page['counts']; old=self.old_counts
        require(active['fileInput']==old['fileInput']+1 and active['fileChange']==old['fileChange']+1 and
                active['sendButtonClicks']==active['formSubmit']==0,'EXACTLY_ONE_NEW_INPUT_AND_CHANGE_REQUIRED')
        new_id=new_op['id'].lower()
        new_names={'riftlet-'+new_id+'.png','riftlet-'+new_id+'.webp'}
        files=[f['qaFile'].lower() for f in page['files'] if f['decoded']]
        fresh=[f for f in files if f in new_names]
        require(len(fresh)==1 and len(files)==len(page['files']) and sorted(f for f in files if f not in new_names)==self.old_files
                and page['allRememberedCardsPresent'] and page['allRememberedNodesPreserved'],'ORIGINAL_AND_NEW_CARDS_REQUIRED')
        events=[e for e in page['observedInputReceipts'] if e.get('knownQAFileName','').lower()=='riftlet-'+new_id+'.png']
        require([e['event'] for e in events]==['input','change'] and all(e['sameInputAsOriginal'] and e.get('sha256') for e in events)
                and events[0]['sha256']==events[1]['sha256']==self.pending['assetSHA256'],'NEW_FILE_ENTRY_NOT_UNIQUE')
        pixels=[r for r in page['pixelEvidence'] if r.get('forLastInput','').lower()=='riftlet-'+new_id+'.png' and r.get('file') and r['file']==r.get('decoded')]
        require(len(pixels)==1,'NEW_FILE_PIXELS_UNCONFIRMED')
        original_epoch=self.seed['originalDraftGeneration']
        seed_epoch_preserved=original_epoch==new_op['originalDraftGeneration']
        result={'status':'PASS' if seed_epoch_preserved else 'PARTIAL','passed':seed_epoch_preserved,'textAndSelectionPassed':True,
                'originalProductEpochFromSeedComparedToNew':seed_epoch_preserved,
                'originalProductEpochPreSample':'previously accepted seed SQLite record, read before new input',
                'pendingSlotEpochDirectlyObservedBeforeNewInput':bool(pre_epoch),
                'websiteWitnessEpoch':after['witnessEpoch'],'productDraftEpochBefore':pre_epoch or 'NOT_OBSERVED',
                'productDraftEpochFromNewSQLiteOperation':new_op['originalDraftGeneration'],
                'seedProductDraftEpoch':self.seed['originalDraftGeneration'],'before':self.before,'after':after,'oldFiles':self.old_files,'newFile':fresh[0],
                'newOperation':new_op,'sourceSHA256':events[0]['sha256'],'pixelDigest':pixels[0]['file']['digest'],'beforeCounts':old,'afterCounts':active}
        self.save('selection-final.json',result)
        return result
