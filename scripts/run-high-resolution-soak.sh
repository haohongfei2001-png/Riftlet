#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "--help" || $# -lt 1 || $# -gt 5 ]]; then
  cat <<'USAGE'
Usage: run-high-resolution-soak.sh NEW_OUTPUT_DIR [SECONDS=0] [INITIAL_CAPTURES=100] [INTERVAL=60] [PREPARED_OUTPUT_DIR]
Builds optimized real Core/Capture/UI modules with testing symbols, then runs a
synthetic-only CLI. No App, windows, browser, login item or production data.
Output must not exist. All original files/logs are retained. A prepared output
may be reused only when the runner and all relevant source hashes still match.
Example smoke: scripts/run-high-resolution-soak.sh /private/new-smoke 0 100 60
Example soak:  scripts/run-high-resolution-soak.sh /private/new-hour 3600 100 60 /private/new-smoke
USAGE
  [[ "${1:-}" == "--help" ]] && exit 0
  exit 64
fi

cd "$(dirname "$0")/.."
riftlet_hires_output="$1"
riftlet_hires_seconds="${2:-0}"
riftlet_hires_captures="${3:-100}"
riftlet_hires_interval="${4:-60}"
riftlet_hires_prepared="${5:-}"

python3 - "$riftlet_hires_output" "$riftlet_hires_seconds" "$riftlet_hires_captures" "$riftlet_hires_interval" <<'PY'
from pathlib import Path
import os,sys
p=Path(sys.argv[1])
assert p.is_absolute() and p.parent.is_dir() and p.parent.resolve()==p.parent, 'Use a new absolute directory below a real existing parent'
assert not p.exists() and not p.is_symlink(), 'Never overwrite prior evidence'
assert 0<=int(sys.argv[2])<=7200 and 12<=int(sys.argv[3])<=200 and 1<=int(sys.argv[4])<=300
os.mkdir(p,0o700)
(p/'runs').mkdir()
PY

riftlet_hires_runner="$riftlet_hires_output/high-resolution-soak"
if [[ -n "$riftlet_hires_prepared" ]]; then
  python3 - "$riftlet_hires_prepared" "$riftlet_hires_output" <<'PY'
from pathlib import Path
import hashlib,json,shutil,subprocess,sys
old,new=map(Path,sys.argv[1:])
identity=json.loads((old/'build-identity.json').read_text())
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
files=[p for area in ['RiftletCore','RiftletCapture','RiftletUI'] for p in Path('Sources',area).rglob('*') if p.is_file()]
files += [Path('Tests/Readiness/NativeHighResolutionSoak.swift')]
current={str(p):sha(p) for p in sorted(files)}
assert current==identity['sourceFiles'], 'Prepared native modules do not match current source bytes'
binary=old/'high-resolution-soak'
assert not binary.is_symlink() and sha(binary)==identity['binarySHA256'], 'Prepared runner hash mismatch'
shutil.copy2(binary,new/'high-resolution-soak')
identity['reusedPreparedIdentitySHA256']=sha(old/'build-identity.json')
identity['executingScriptSHA256']=sha(Path('scripts/run-high-resolution-soak.sh'))
identity['executingCheckoutCommit']=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
(new/'build-identity.json').write_text(json.dumps(identity,indent=2)+'\n')
PY
else
  swift build --build-system native -c release -Xswiftc -enable-testing \
    --scratch-path "$riftlet_hires_output/build" --target RiftletUI > "$riftlet_hires_output/build.log" 2>&1
  riftlet_hires_bin="$(swift build --build-system native -c release --scratch-path "$riftlet_hires_output/build" --show-bin-path)"
  xcrun swiftc -O -parse-as-library -I "$riftlet_hires_bin/Modules" -I Sources/CSQLite \
    Tests/Readiness/NativeHighResolutionSoak.swift \
    "$riftlet_hires_bin"/RiftletCore.build/*.o "$riftlet_hires_bin"/RiftletCapture.build/*.o \
    "$riftlet_hires_bin"/RiftletUI.build/*.o -lsqlite3 -o "$riftlet_hires_runner" \
    > "$riftlet_hires_output/harness-build.log" 2>&1
  python3 - "$riftlet_hires_output" <<'PY'
from pathlib import Path
import hashlib,json,subprocess,sys
out=Path(sys.argv[1])
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
files=[p for area in ['RiftletCore','RiftletCapture','RiftletUI'] for p in Path('Sources',area).rglob('*') if p.is_file()]
files += [Path('Tests/Readiness/NativeHighResolutionSoak.swift')]
identity={'schema':1,'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
 'sourceFiles':{str(p):sha(p) for p in sorted(files)},'binarySHA256':sha(out/'high-resolution-soak'),
 'moduleBuild':'release optimization with -enable-testing; no product source modification',
 'harnessBuild':'swiftc -O; actual three native module object files',
 'scriptSHA256':sha(Path('scripts/run-high-resolution-soak.sh')),
 'swiftVersion':subprocess.check_output(['xcrun','swiftc','--version'],text=True).strip()}
(out/'build-identity.json').write_text(json.dumps(identity,indent=2)+'\n')
PY
fi

riftlet_hires_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
riftlet_hires_root="$riftlet_hires_output/runs/riftlet-hires-$riftlet_hires_id"
set +e
python3 - "$riftlet_hires_output" "$riftlet_hires_root" "$riftlet_hires_captures" "$riftlet_hires_seconds" "$riftlet_hires_interval" <<'PY'
from pathlib import Path
import datetime,json,os,subprocess,sys,time
out=Path(sys.argv[1]); started=time.monotonic()
record={'schema':1,'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'completed':False,'timedOut':False,'maximumSeconds':int(sys.argv[4])+600,
 'concurrentWork':os.environ.get('RIFTLET_HIRES_CONCURRENT_WORK','Not controlled; no other-process CPU attribution')}
with (out/'runtime.log').open('w') as log:
 process=subprocess.Popen([str(out/'high-resolution-soak'),*sys.argv[2:]],stdout=log,stderr=subprocess.STDOUT)
 record['pid']=process.pid
 (out/'process.json').write_text(json.dumps(record,indent=2)+'\n')
 try: code=process.wait(timeout=record['maximumSeconds'])
 except subprocess.TimeoutExpired:
  record['timedOut']=True; process.terminate()
  try: process.wait(timeout=5)
  except subprocess.TimeoutExpired: process.kill(); process.wait()
  code=124
 record.update(completed=True,exitCode=code,actualSeconds=time.monotonic()-started,
  finishedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat())
 (out/'process.json').write_text(json.dumps(record,indent=2)+'\n')
sys.exit(code)
PY
riftlet_hires_exit=$?
set -e

python3 - "$riftlet_hires_output" "$riftlet_hires_root" "$riftlet_hires_exit" <<'PY'
from pathlib import Path
import hashlib,json,shutil,sqlite3,stat,subprocess,sys,time
out,root=map(Path,sys.argv[1:3]); exitcode=int(sys.argv[3])
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  while block:=f.read(1024*1024): h.update(block)
 return h.hexdigest()
result={'schema':1,'exitCode':exitcode,'rootBasename':root.name,'completed':False,'result':'FAIL',
 'binarySHA256':sha(out/'high-resolution-soak'),'productionDataAccess':False,'verifiedUTC':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
process=json.loads((out/'process.json').read_text())
result['timedOut']=process['timedOut']; result['concurrentWork']=process['concurrentWork']
result['processRecordSHA256']=sha(out/'process.json')
def database_snapshot(label):
 verification=out/('verification-db-'+label); verification.mkdir()
 for suffix in ['', '-wal', '-shm']:
  p=root/'private'/('queue.sqlite'+suffix)
  if p.exists(): shutil.copy2(p,verification/p.name)
 connection=sqlite3.connect((verification/'queue.sqlite').as_uri()+'?mode=ro',uri=True)
 assert connection.execute('PRAGMA quick_check').fetchall()==[('ok',)]
 assert connection.execute('PRAGMA foreign_key_check').fetchall()==[]
 tables=[r[0] for r in connection.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
 counts={name:connection.execute('SELECT count(*) FROM "'+name.replace('"','""')+'"').fetchone()[0] for name in tables}
 unknown=connection.execute("SELECT * FROM operations WHERE phase='unknown'").fetchall()
 assert len(unknown)==1
 def cell(v):
  if v is None: return ['null']
  if isinstance(v,bytes): return ['blob',v.hex()]
  if isinstance(v,int): return ['integer',v]
  if isinstance(v,float): return ['real',v.hex()]
  return ['text',v]
 rows={}
 for name in tables:
  encoded=sorted(json.dumps([cell(v) for v in row],ensure_ascii=False,separators=(',',':')) for row in connection.execute('SELECT * FROM "'+name.replace('"','""')+'"'))
  rows[name]=hashlib.sha256(json.dumps(encoded,separators=(',',':')).encode()).hexdigest()
 schema=connection.execute('SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name').fetchall()
 snapshot={'quickCheck':'ok','foreignKeyViolations':0,'tables':counts,'typedRowHashes':rows,
  'schemaSHA256':hashlib.sha256(json.dumps(schema,separators=(',',':')).encode()).hexdigest(),
  'unknownFullRowSHA256':hashlib.sha256(json.dumps(unknown,separators=(',',':')).encode()).hexdigest()}
 connection.close()
 return snapshot
try:
 report=json.loads((root/'report.json').read_text())
 result['reportSHA256']=sha(root/'report.json'); result['nativeResult']=report['result']
 assert exitcode==0 and report['completed'] and report['result']=='PASS_SCOPED_HIGH_RESOLUTION_READINESS'
 before=database_snapshot('before-restart')
 (out/'pre-restart-database.json').write_text(json.dumps(before,indent=2)+'\n')
 restart=subprocess.run([str(out/'high-resolution-soak'),'--verify-restart',str(root)],capture_output=True,text=True,timeout=60)
 (out/'restart-runtime.log').write_text(restart.stdout+restart.stderr)
 result['restartExitCode']=restart.returncode
 assert restart.returncode==0
 restarted=json.loads((root/'restart-report.json').read_text())
 result['restartReportSHA256']=sha(root/'restart-report.json')
 assert restarted['completed'] and restarted['result']=='PASS_SCOPED_FRESH_PROCESS_RECOVERY'
 assert restarted['pid']!=report['pid'], 'Restart must be a fresh process'
 after=database_snapshot('after-restart')
 result['database']=after
 result['allTypedRowsAndSchemaUnchangedAcrossFreshProcess']=before==after
 assert before==after, 'Fresh process changed database rows/schema'
 assert after['tables']['assets']==report['finalCaptureCount'] and after['tables']['operations']==1 and after['tables']['upload_starts']==0
 assets=json.loads((root/'final-assets.json').read_text())
 for record in assets:
  image=record['image']; p=root/'private/media'/image['fileName']
  assert p.is_file() and p.stat().st_size==image['byteCount'] and sha(p)==image['sha256']
 files={}
 for p in sorted(root.rglob('*')):
  mode=p.lstat().st_mode
  assert not stat.S_ISLNK(mode)
  if p.is_file(): files[p.relative_to(root).as_posix()]={'sha256':sha(p),'size':p.stat().st_size,'mode':format(stat.S_IMODE(mode),'04o')}
 (out/'file-manifest.json').write_text(json.dumps({'schema':1,'files':files},indent=2)+'\n')
 result['fileManifestSHA256']=sha(out/'file-manifest.json'); result['regularFiles']=len(files)
 result['mediaVerified']=len(assets); result['completed']=True; result['result']='PASS_SCOPED_HIGH_RESOLUTION_READINESS'
except Exception as error:
 result['failure']=repr(error)
(out/'runner-result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
sys.exit(0 if result['completed'] else 1)
PY
