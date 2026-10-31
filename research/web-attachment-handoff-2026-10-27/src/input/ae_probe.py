#!/usr/bin/env python3
"""Bounded Apple Events JS runner. Does not activate apps or set preferences."""
import json,subprocess,time,sys
from pathlib import Path
root=Path(__file__).resolve().parent.parent
meta=json.loads((root/'run/web-target.json').read_text())
w,tab,old=meta['stdout'].split(',')
script=Path(sys.argv[1]).resolve()
start=time.monotonic()
try:
 p=subprocess.run(['osascript',str(root/'src/web-evaluate.applescript'),w,tab,str(script)],text=True,capture_output=True,timeout=12)
 result={'event':script.stem,'monotonicSeconds':start,'durationMs':round((time.monotonic()-start)*1000),'exitCode':p.returncode,'result':None,'error':p.stderr.strip() or None}
 try: result['result']=json.loads(p.stdout)
 except ValueError: result['result']=p.stdout.strip()
except subprocess.TimeoutExpired:
 result={'event':script.stem,'monotonicSeconds':start,'result':'UNKNOWN','reason':'TRANSPORT_TIMEOUT_NO_RETRY'}
with (root/'run/ae-events.ndjson').open('a') as f:f.write(json.dumps(result,ensure_ascii=False)+'\n')
print(json.dumps(result,ensure_ascii=False))
