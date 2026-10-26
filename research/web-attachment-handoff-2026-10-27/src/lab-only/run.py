from pathlib import Path
import json,subprocess,sys,time,os
r=Path(__file__).resolve().parent.parent;c=json.loads((r/'run/config.json').read_text());p=Path(sys.argv[1]).resolve();e={'event':p.stem,'windowId':c['windowId'],'tabId':c['tabId'],'monotonicSeconds':time.monotonic()}
try:
 x=subprocess.run(['osascript',str(r/'src/web-evaluate.applescript'),c['windowId'],c['tabId'],str(p)],capture_output=True,text=True,timeout=12);e.update(exitCode=x.returncode,error=x.stderr.strip() or None)
 try:e['result']=json.loads(x.stdout)
 except ValueError:e['result']=x.stdout.strip()
except subprocess.TimeoutExpired:e.update(result='UNKNOWN',reason='TIMEOUT_NO_REPLAY')
with (r/'run/transport.ndjson').open('a') as f:f.write(json.dumps(e,ensure_ascii=False)+'\n');f.flush();os.fsync(f.fileno())
print(json.dumps(e,ensure_ascii=False))
