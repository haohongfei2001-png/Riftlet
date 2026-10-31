from pathlib import Path
import json,sys,os,time,base64,subprocess
r=Path(__file__).resolve().parent.parent;c=json.loads((r/'run/config.json').read_text());label=sys.argv[1];f=next(x for x in c['fixtures'] if x['label']==label)
rows=[json.loads(l) for l in (r/'run/transport.ndjson').read_text().splitlines()];nonce=next(x['result']['documentNonce'] for x in reversed(rows) if x['event']=='observer' and x.get('exitCode')==0)
intent=r/'run'/('intent-'+f['assetId']+'.json')
with intent.open('x') as o:json.dump({'label':label,'fixture':f,'documentNonce':nonce,'windowId':c['windowId'],'tabId':c['tabId'],'phase':'DISPATCH_INTENT','retryAllowed':False,'time':time.monotonic()},o);o.flush();os.fsync(o.fileno())
a={'label':label,'base64':base64.b64encode(Path(f['path']).read_bytes()).decode(),'expectedNonce':nonce};p=r/'run'/('dispatch-'+label+'-once.js');p.write_text('JSON.stringify(globalThis.__riftletExceptions.dispatch('+json.dumps(a)+'));')
x=subprocess.run([sys.executable,str(r/'src/run.py'),str(p)],capture_output=True,text=True,timeout=15);print(x.stdout,end='');print(x.stderr,end='',file=sys.stderr)
