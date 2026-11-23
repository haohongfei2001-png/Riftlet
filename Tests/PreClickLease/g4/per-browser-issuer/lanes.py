"""Original scopes and scheduling history. All pointer mutations require the shared GUI flock."""
import hashlib, json, os, re, sqlite3, tempfile, time
from pathlib import Path

FAMILIES={'chrome':('g1','g4c'),'edge':('g2','g4c','b4')}
def check(x,why):
    if not x:raise ValueError(why)
def read(p):return json.loads(p.read_bytes())
def known(f,k):check(k in FAMILIES.get(f,()),'UNKNOWN_LANE')
def root_of(base,row):
    f,k=row['family'],row['case'];known(f,k);r=Path(row['root'])
    allowed=(f=='edge' and k=='g4c' and r.name=='g4c-first') or re.fullmatch(k+r'-[a-f0-9]{32}',r.name)
    check(r.parent==base and r==r.resolve() and allowed and row.get('preInput') is True and
          row.get('entry')=='new-sole-verified-native-window','UNVERIFIED_SCOPE_PATH')
    return r
def syncdir(p):
    fd=os.open(p,os.O_RDONLY)
    try:os.fsync(fd)
    finally:os.close(fd)
def index(base,row,write_new):
    root=root_of(base,row);exe=base/'execution';folder=exe/'lane-scopes';lane=folder/(row['family']+'-'+row['case'])
    for p in (folder,lane):
        check(p.resolve()==p,'UNSAFE_SCOPE_DIRECTORY')
        if not p.exists():p.mkdir(mode=0o700);syncdir(p.parent)
    p=lane/(root.name+'.json')
    if not p.exists():write_new(p,row)
    check(p.resolve()==p and read(p)==row,'ORIGINAL_SCOPE_INDEX_CHANGED')
    return p
def snapshot_pointer(base,write_new):
    p=base/'active-scope.json'
    if p.exists():
        check(p.resolve()==p,'UNSAFE_ACTIVE_SCOPE')
        return index(base,read(p),write_new)
def issued(base,row):
    root=root_of(base,row);s=root/'signed61'/row['family']
    return (root/'business-claim.json').exists() or (root/'g4c-live-intent.json').exists() or any(s.glob('live-*'))
def finished(base,row):
    r=root_of(base,row)
    from retire_missing import attested
    return attested(base,row) or any(p.is_file() and p.resolve()==p and read(p)==row for p in [r/'closed-scope.json',r/'preserved-scope.json'])
def history(base,f,k):
    known(f,k)
    lane=base/'execution/lane-scopes'/(f+'-'+k)
    check(lane.resolve()==lane,'UNSAFE_SCOPE_INDEX')
    rows=[]
    for p in sorted(lane.glob('*.json')):
        row=read(p);r=root_of(base,row)
        check(p.resolve()==p and p.stem==r.name and row['family']==f and row['case']==k,'MISMATCHED_ORIGINAL_INDEX')
        rows.append(row)
    return rows
def original(base,f,k):
    rows=[r for r in history(base,f,k) if not finished(base,r)]
    check(len(rows)<=1,'MULTIPLE_UNCLOSED_ORIGINAL_SCOPES')
    return rows[0] if rows else None
def point(base,row,write_new):
    # Preserve old index first. A crash at any boundary leaves at least one recoverable reference.
    old=snapshot_pointer(base,write_new);p=base/'active-scope.json'
    if row is None:
        if old:p.unlink();syncdir(base)
        return
    src=index(base,row,write_new)
    if p.exists() and read(p)==row:return
    with tempfile.TemporaryDirectory(dir=base,prefix='.lane-pointer-') as temp:
        copy=Path(temp)/'pointer';os.link(src,copy);os.replace(copy,p);syncdir(base)
def init(db):
    db.executescript("""CREATE TABLE IF NOT EXISTS lane_state(family TEXT,request TEXT,epoch INTEGER,proof TEXT,proof_json TEXT,utc REAL,PRIMARY KEY(family,request));
      CREATE TABLE IF NOT EXISTS lane_attempts(id INTEGER PRIMARY KEY,family TEXT,request TEXT,epoch INTEGER,utc REAL,environment TEXT,stage TEXT);
      CREATE INDEX IF NOT EXISTS lane_last_attempt ON lane_attempts(family,request,id);""")
def observe(db,f,k,s):
    from gui_sample import CHECKS
    proof={'digest':s['digest'],'target':s.get('targetKey'),'held':s.get('heldCase'),'checks':dict((key,s['checks'][key]) for key in CHECKS),
           'ready':s['ready'],'eligible':s['environment']['eligibleForPreparation'],'identity':s.get('identityProof'),
           'unavailable':s.get('scopeReadError') is not None}
    payload=json.dumps(proof,sort_keys=True,separators=(',',':'))
    key=hashlib.sha256(payload.encode()).hexdigest()
    old=db.execute('SELECT epoch,proof FROM lane_state WHERE family=? AND request=?',(f,k)).fetchone()
    epoch=(old[0]+int(old[1]!=key)) if old else 1
    with db:db.execute('INSERT OR REPLACE INTO lane_state VALUES(?,?,?,?,?,?)',(f,k,epoch,key,payload,time.time()))
    return epoch
def eligible_order(db,items,now):
    selected=[]
    for order,(f,k,s,epoch) in enumerate(items):
        if not s['environment']['eligibleForPreparation']:continue
        old=db.execute('SELECT epoch,utc,stage FROM lane_attempts WHERE family=? AND request=? ORDER BY id DESC LIMIT 1',(f,k)).fetchone()
        age=now-old[1] if old else float('inf')
        # A new proof can be considered immediately. Stable pre-input scopes are rechecked after bounded backoff.
        if old and old[0]==epoch and age<180:continue
        # A ready proof has precedence. Normal acceptance of each browser precedes speculative G4 fallback.
        # Within equal availability, round-robin by last attempt. Fresh scopes cannot starve.
        selected.append(((not s['ready'],not s['environment'].get('familyFrontmost',False),
                          k=='g4c' and f=='chrome',old[1] if old else -1,order),(f,k,s,epoch)))
    return [x for _,x in sorted(selected,key=lambda v:v[0])]
def attempted(db,f,k,epoch,s,stage):
    with db:db.execute('INSERT INTO lane_attempts(family,request,epoch,utc,environment,stage) VALUES(?,?,?,?,?,?)',
                       (f,k,epoch,time.time(),s['digest'],stage))
