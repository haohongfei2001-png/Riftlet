#!/usr/bin/env python3
"""One-shot experiment. Durable intent is written before any external input.
Existing intents are never replayed; query the observer instead.
"""
from pathlib import Path
import json,sys,uuid,base64,subprocess,os,time
r=Path(__file__).resolve().parent.parent
label=sys.argv[1]
f=next(x for x in json.loads((r/'fixtures/manifest.json').read_text()) if x['label']==label)
ops=r/'run/operations';ops.mkdir(exist_ok=True)
intent=ops/(f['assetId']+'.json')
if intent.exists():raise SystemExit('UNRESOLVED_OR_PRIOR_OPERATION: NO_REPLAY')
records=[json.loads(l) for l in (r/'run/ae-events.ndjson').read_text().splitlines()]
nonce=next(x['result']['documentNonce'] for x in reversed(records) if x['event']=='configure' and isinstance(x['result'],dict))
op=str(uuid.uuid4())
args={'operationId':op,'name':f['name'],'mime':f['mime'],'expectedNonce':nonce,'base64':base64.b64encode((r/'fixtures'/f['name']).read_bytes()).decode()}
record={'operationId':op,'assetId':f['assetId'],'target':json.loads((r/'run/web-target.json').read_text())['stdout'].split(',')[:2],'documentNonce':nonce,'phase':'DISPATCH_INTENT','result':'UNKNOWN','monotonicSeconds':time.monotonic()}
with intent.open('x') as out:
 json.dump(record,out,indent=2);out.flush();os.fsync(out.fileno())
script=r/'run/dispatch-once.js';script.write_text('JSON.stringify(globalThis.__riftletProbe.dispatch('+json.dumps(args)+'));')
p=subprocess.run([sys.executable,str(r/'src/ae_probe.py'),str(script)],capture_output=True,text=True)
print(p.stdout,end='');print(p.stderr,end='',file=sys.stderr)
