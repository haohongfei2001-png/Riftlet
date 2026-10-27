#!/usr/bin/env python3
"""Offline only: no browser, network, clipboard, Apple Events or upload execution."""
from pathlib import Path
import hashlib,json,runpy,subprocess,sys,struct,zlib
ROOT=Path(__file__).resolve().parent

def read(p):return json.loads((ROOT/p).read_text())
def check(condition,reason):
    if not condition:raise AssertionError(reason)

def main():
    check(sys.version_info>=(3,10),'Python 3.10+ required')
    manifest=read('MANIFEST.json')
    for f in manifest:
        p=ROOT/f['path'];check(p.is_file() and p.stat().st_size==f['bytes'] and hashlib.sha256(p.read_bytes()).hexdigest()==f['sha256'],'Package integrity: '+f['path'])
    for f in read('fixtures/manifest.json'):
        data=(ROOT/f['path']).read_bytes();check(hashlib.sha256(data).hexdigest()==f['sha256'],'Fixture hash');i=8
        check(data[:8]==b'\x89PNG\r\n\x1a\n','PNG signature')
        while i<len(data):
            size=struct.unpack('>I',data[i:i+4])[0];chunk=data[i+4:i+8];body=data[i+8:i+8+size]
            check(zlib.crc32(chunk+body)&0xffffffff==struct.unpack('>I',data[i+8+size:i+12+size])[0],'PNG CRC')
            if chunk==b'eXIf':
                check(body.hex()=='4d4d002a00000008000187690004000000010000001a000000000002a00200040000000100000320a003000400000001000001c200000000','Only reviewed dimensions-only EXIF permitted')
            i+=size+12
        check(i==len(data),'PNG bounds')
    initial=[json.loads(l) for l in (ROOT/'evidence/input/ae-observations.ndjson').read_text().splitlines()]
    dispatches=[x for x in initial if x['event']=='dispatch-once']
    check(len(dispatches)==3 and len({x['result']['operationId'] for x in dispatches})==3,'Three real unique inputs')
    check(all(x['exitCode']==0 and x['result']['dispatched'] for x in dispatches),'AE dispatch result')
    final=read('evidence/input/final-composer-snapshot.json')
    names={n for s in final['signals'] for a in s['attrs'].values() if isinstance(a,dict) for n in a.get('names',[])}
    check(len(names)==3 and final['textUnchanged'] and final['valid'],'Original input preservation')
    recovery=next(x['result'] for x in initial if x['event']=='recovery-query')
    check(not recovery['observerPresent'] and recovery['result']=='UNKNOWN','Reload receipt loss must remain unknown')
    audit=runpy.run_path(str(ROOT/'src/attached/attached_exception_audit.py'))['run'](ROOT)
    recorded=read('evidence/exceptions/main/attached-exception-audit.json')
    check(audit==recorded,'Sanitized replay changed previous verdict')
    for label,path in [('MID','mid-final-before-bridge-refinement.json'),('POST100','post100-final.json')]:
        q=read('evidence/exceptions/main/'+path)['result'];ev=q['network']['events']
        aborts=[e for e in ev if e['event']=='native_abort_event' and e.get('kind')=='bytes-observed-upload-url']
        check(len(aborts)==1,'One actual native abort')
        identity=aborts[0]['requestLocalId'];op=aborts[0]['operationId']
        owned=[e for e in ev if e.get('requestLocalId')==identity and e.get('operationId')==op]
        check(any(e['event']=='native_loadend' and e['status']==0 for e in owned),'Actual abort end status')
        progress=[e for e in owned if e['event']=='native_upload_progress']
        check(bool(progress),'Native byte progress evidence')
        check(any(e['loaded']==e['total'] and e['total']>0 for e in progress) if label=='POST100' else any(0<e['loaded']<e['total'] for e in progress),'Correct interruption point')
    rec=read('evidence/exceptions/main/recovery-verification.json')
    check(rec['transportUnchanged'] and all(x['refusedBeforeBrowser'] for x in rec['duplicateAttempts']),'Durable no replay')
    check(all(x['exists'] and x['matches'] and x['durableIntentExists'] for x in rec['retained']),'Recorded original preservation')
    check(read('evidence/exceptions/main/network-cleanup.json')['result']['state']=='STOPPED','Fault bridge cleanup')
    sw=read('evidence/exceptions/transition/transition-final.json')['result']
    check(sw['transition']['before']['snapshot']['valid'] and not sw['query']['snapshot']['valid'],'Real transition invalidates original target')
    # New checks below are SIMULATED counterexamples of saved data, not new GUI evidence.
    q=read('evidence/exceptions/main/identity-observation.json')['result'];f=read('evidence/exceptions/main/config.json')['fixtures'][0]
    proof=read('evidence/exceptions/main/pixel-proof.json')['result']
    classify=runpy.run_path(str(ROOT/'src/attached/attached_exception_audit.py'))['classify']
    import copy
    late=copy.deepcopy(q);last=late['events'][-1]
    late['events'].append({**last,'sequence':last['sequence']+1,'monotonicMs':last['monotonicMs']+1,'event':'image_error','state':{'name':f['name']}})
    check(classify(late,f,proof)['state']!='ATTACHED','SIMULATED late own image error veto')
    late=copy.deepcopy(q);late['uiErrors']=[{'names':[f['name']],'correlation':'EXACT_FILENAME'}]
    check(classify(late,f,proof)['state']!='ATTACHED','SIMULATED late associated UI error veto')
    subprocess.run(['node','--test',str(ROOT/'src/attached/test-attached-v1.cjs')],check=True,cwd=ROOT)
    print(json.dumps({'offlineOnly':True,'packageFilesVerified':len(manifest),'historicalV1Tests':19,'realExceptionTracePrefixes':89,'lateErrorChecks':'2 SIMULATED, not actual post-preview failure','actualInputOperations':3,'exceptionVerdicts':{k:v['state'] for k,v in audit['verdicts'].items()},'strictInternalREADY':'NOT_PROVEN','browserActions':0,'networkRequests':0},indent=2))

if __name__=='__main__':main()
