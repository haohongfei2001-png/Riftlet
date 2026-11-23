#!/usr/bin/env python3
"""Durable scheduler for the signed build 60 QA host. No browser control in this process."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import signal
import sqlite3
import stat
import subprocess
import sys
import time

SOURCE = '711cee3a1c7033ce4925082a83099b00da7087c6'
DMG = '5a934119d6e65cbe82a62f5f208a2b95a200fa0cf170225ccd4e9016b1c0b54e'
CASES = {'chrome': ('g1',), 'edge': ('g2', 'g4c', 'b4')}
CHECKS = ('originalProcessBirth', 'dedicatedSingleTab', 'nativeForeground', 'nativeWindowVisible',
          'cgWindowOnScreen', 'axOriginalWindow', 'originalTabSelected', 'documentVisible',
          'documentFocused', 'signedIn', 'composer', 'uploadEntry')
HEX = re.compile(r'^[a-f0-9]{64}$')
STOP = False


def now():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as reader:
        for chunk in iter(lambda: reader.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def need(condition, reason):
    if not condition:
        raise ValueError(reason)


def secure_dir(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    s = path.lstat()
    need(stat.S_ISDIR(s.st_mode) and s.st_uid == os.getuid() and not s.st_mode & 0o077,
         'STATE_DIRECTORY_NOT_PRIVATE')


@contextmanager
def locked(path):
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        st = os.fstat(fd)
        need(stat.S_ISREG(st.st_mode) and st.st_uid == os.getuid() and not st.st_mode & 0o077,
             'UNSAFE_LOCK_FILE')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            yield None
            return
        yield fd
    finally:
        # Closing, rather than LOCK_UN, preserves inherited leases if this scheduler exits first.
        os.close(fd)


def write_private(path, value):
    data = (json.dumps(value, sort_keys=True) + '\n').encode()
    with path.open('xb') as out:
        os.chmod(path, 0o600)
        out.write(data)
        out.flush()
        os.fsync(out.fileno())
    fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def db_open(state):
    secure_dir(state)
    db = sqlite3.connect(state/'supervisor.sqlite', timeout=5)
    db.execute('PRAGMA synchronous=FULL')
    db.executescript('''
      CREATE TABLE IF NOT EXISTS settings(k TEXT PRIMARY KEY,v TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS attempts(id TEXT PRIMARY KEY, family TEXT NOT NULL, task TEXT NOT NULL,
        target TEXT NOT NULL, transition INTEGER NOT NULL, status TEXT NOT NULL, receipt TEXT);
      CREATE UNIQUE INDEX IF NOT EXISTS one_live_case ON attempts(task)
        WHERE status IN ('CLAIMED','INCONCLUSIVE','PASS');
      CREATE TABLE IF NOT EXISTS preparations(family TEXT,task TEXT,transition INTEGER,PRIMARY KEY(family,task,transition));
      CREATE TABLE IF NOT EXISTS samples(family TEXT PRIMARY KEY,state TEXT NOT NULL,transition INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS probes(family TEXT PRIMARY KEY,observations INTEGER,valid INTEGER,last_at TEXT);
      CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY,at TEXT,kind TEXT,family TEXT,detail TEXT);
    ''')
    return db


def event(db, kind, family='', detail=''):
    db.execute('INSERT INTO events(at,kind,family,detail) VALUES(?,?,?,?)', (now(),kind,family,detail))


def setting(db, key, default=None):
    row = db.execute('SELECT v FROM settings WHERE k=?',(key,)).fetchone()
    return row[0] if row else default


def put(db, key, value):
    db.execute('INSERT INTO settings VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v',(key,value))


def configure(db, state, host, lock_path):
    host = host.resolve(strict=True)
    need(host.is_file() and os.access(host,os.X_OK), 'HOST_NOT_EXECUTABLE')
    lock_path = lock_path.absolute()
    secure_dir(lock_path.parent)
    manifest = host.parent/'host-components.json'
    manifest_sha = digest(manifest) if manifest.is_file() else ''
    with locked(lock_path.parent/'supervisor-registration.lock') as fd, db:
        need(fd is not None,'CONFIGURATION_IN_PROGRESS')
        existing = setting(db,'host')
        need(existing is None or (existing == str(host) and setting(db,'hostSHA') == digest(host) and
             setting(db,'guiLock') == str(lock_path) and setting(db,'manifestSHA','') == manifest_sha),
             'REGISTERED_HOST_OR_LOCK_DIFFERS')
        marker = lock_path.parent/'build60-supervisor-owner.json'
        enrollment = setting(db,'enrollment')
        if marker.exists():
            owner = json.loads(marker.read_bytes())
            need(owner.get('state')==str(state) and enrollment and owner.get('enrollment')==enrollment and
                 owner.get('dmgSHA256')==DMG,'ANOTHER_OR_LOST_DURABLE_STATE')
        if existing is not None and setting(db,'registeredState') is None and marker.exists():
            put(db,'registeredState',str(state.resolve()))
        if existing is None:
            enrollment = secrets.token_hex(16)
            for key,val in [('host',str(host)),('hostSHA',digest(host)),('guiLock',str(lock_path)),('armed','0'),
                            ('stop','0'),('enrollment',enrollment),('registeredState',str(state.resolve())),('manifestSHA',manifest_sha)]:
                put(db,key,val)
            event(db,'CONFIGURED')
        db.commit()
        if not marker.exists():
            write_private(marker,{'state':str(state),'enrollment':enrollment,'dmgSHA256':DMG})


def owns_state(state, db):
    """A copied database never becomes another dispatcher for the same private GUI lease."""
    marker=Path(setting(db,'guiLock')).parent/'build60-supervisor-owner.json'
    canonical=str(state.resolve())
    recorded=setting(db,'registeredState')
    if recorded not in (None,canonical):
        return False
    try:
        if not marker.exists() and recorded==canonical:
            # The private lock directory can be recreated on login. Only the
            # previously registered durable database may re-establish the marker.
            secure_dir(marker.parent)
            with locked(marker.parent/'supervisor-registration.lock') as fd:
                if fd is None:
                    return False
                if not marker.exists():
                    write_private(marker,{'state':canonical,'enrollment':setting(db,'enrollment'),'dmgSHA256':DMG})
        own=json.loads(marker.read_bytes())
        matches=(Path(own['state']).samefile(state) and own['enrollment']==setting(db,'enrollment') and
                 own['dmgSHA256']==DMG)
        if matches and recorded is None:
            with db:
                put(db,'registeredState',canonical)
        return matches
    except (OSError,ValueError,KeyError,TypeError):
        return False


def update_pin(db, expected_host, expected_manifest):
    with db:
        db.execute('BEGIN IMMEDIATE')
        need(setting(db,'armed')=='0', 'DISARM_BEFORE_HOST_UPDATE')
        host=Path(setting(db,'host'))
        manifest=host.parent/'host-components.json'
        need(HEX.fullmatch(expected_host) and HEX.fullmatch(expected_manifest) and
             digest(host)==expected_host and digest(manifest)==expected_manifest,'HOST_UPDATE_HASH_MISMATCH')
        put(db,'hostSHA',expected_host)
        put(db,'manifestSHA',expected_manifest)
        event(db,'HOST_PIN_UPDATED',detail=expected_manifest)


def command(db, args, gui_fd=None, timeout=25):
    host = Path(setting(db,'host'))
    need(digest(host) == setting(db,'hostSHA'), 'HOST_FINGERPRINT_CHANGED')
    manifest=host.parent/'host-components.json'
    expected_manifest=setting(db,'manifestSHA','')
    need((digest(manifest) if manifest.is_file() else '')==expected_manifest,'HOST_MANIFEST_CHANGED')
    environment = dict(os.environ)
    environment.pop('RIFTLET_GUI_LOCK_FD',None)
    inherited = ()
    if gui_fd is not None:
        environment.update(RIFTLET_GUI_LOCK_FD=str(gui_fd),RIFTLET_GUI_LOCK_PATH=setting(db,'guiLock'))
        inherited = (gui_fd,)
    # Never inherit terminal input or copy raw site/host output into the transition log.
    proc = subprocess.Popen([str(host), *args], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, env=environment, pass_fds=inherited)
    try:
        raw, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        if gui_fd is None:
            proc.kill()  # only the owned read-only sampler
            proc.communicate()
        # Never kill or retry a potentially active input. The host retains the GUI lease.
        raise ValueError('HOST_TIMEOUT')
    need(proc.returncode == 0 and len(raw) <= 65536, 'HOST_RESULT_UNAVAILABLE')
    result = json.loads(raw)
    need(isinstance(result,dict), 'HOST_INVALID_JSON')
    return result


def sample(db,family):
    nonce=secrets.token_hex(16)
    start=time.monotonic()
    data=command(db,['sample',family,nonce])
    need(time.monotonic()-start < 25 and data.get('nonce')==nonce and data.get('family')==family and
         isinstance(data.get('digest'),str) and HEX.fullmatch(data['digest']), 'STALE_OR_UNBOUND_SAMPLE')
    env=data.get('environment',{})
    checks=data.get('checks',{})
    need(type(data.get('ready')) is bool and isinstance(env,dict) and
         type(env.get('eligibleForPreparation')) is bool, 'INCOMPLETE_PROBE')
    # Even a host-level ready flag alone cannot authorize either browser.
    ready=(data.get('ready') is True and isinstance(checks,dict) and
           all(checks.get(k) is True for k in CHECKS) and
           isinstance(data.get('targetKey'),str) and HEX.fullmatch(data['targetKey']) is not None)
    need(data['ready'] is False or ready, 'INCONSISTENT_POSITIVE_PROBE')
    held=data.get('heldCase')
    need(held is None or held in CASES[family], 'UNKNOWN_HELD_CASE')
    need(not ready or held is not None, 'READY_SCOPE_HAS_NO_BOUND_CASE')
    return {'digest':data['digest'],'heldCase':held,'ready':ready,'targetKey':data.get('targetKey') if ready else None,
            'preparable':isinstance(env,dict) and env.get('eligibleForPreparation') is True}


def transition(db,family,value):
    encoded=json.dumps(value,sort_keys=True,separators=(',',':'))
    old=db.execute('SELECT state,transition FROM samples WHERE family=?',(family,)).fetchone()
    if old and old[0]==encoded:
        return old[1],False
    number=old[1] if old else 0
    with db:
        # A failed read and later successful read of the same desktop must not
        # grant another preparation. Advance only on a positively sampled change.
        if 'digest' in value and setting(db,'lastWitness:'+family)!=encoded:
            put(db,'lastWitness:'+family,encoded)
            number+=1
        db.execute('INSERT INTO samples VALUES(?,?,?) ON CONFLICT(family) DO UPDATE SET state=excluded.state,transition=excluded.transition',
                   (family,encoded,number))
        event(db,'ENVIRONMENT',family,encoded)
    return number,True


def next_case(db,family,number,held):
    for task in ((held,) if held else CASES[family]):
        if db.execute("SELECT 1 FROM attempts WHERE task=? AND (status IN ('PASS','CLAIMED','INCONCLUSIVE') OR transition=?)",
                      (task,number)).fetchone():
            continue
        return task
    return None


def read_result(state, claim, response):
    for k in ('nonce','family','case','targetKey'):
        need(response.get(k)==claim[k], 'HOST_RESPONSE_SCOPE_MISMATCH')
    rawpath=response.get('receiptPath')
    need(isinstance(rawpath,str), 'MISSING_OWNED_TERMINAL_RECEIPT')
    path=Path(rawpath)
    expected=state/('terminal-'+claim['attemptID']+'.json')
    need(path==expected and not path.is_symlink() and path.is_file() and path.stat().st_size<=65536,
         'UNBOUND_TERMINAL_RECEIPT')
    expected_digest=response.get('receiptSHA256')
    need(isinstance(expected_digest,str) and HEX.fullmatch(expected_digest) and digest(path)==expected_digest,
         'TERMINAL_RECEIPT_HASH_MISMATCH')
    receipt=json.loads(path.read_bytes())
    for k in ('family','case','nonce','targetKey','attemptID','dmgSHA256'):
        need(claim[k]==receipt.get(k), 'TERMINAL_RECEIPT_SCOPE_MISMATCH')
    result=receipt.get('outcome')
    need(result==response.get('outcome') and result in ('PASS','STOPPED_BEFORE_INPUT','INCONCLUSIVE'),
         'TERMINAL_RESULT_INVALID')
    if result=='STOPPED_BEFORE_INPUT':
        need(type(receipt.get('productInputCount')) is int and receipt['productInputCount']==0 and
             receipt.get('inputBoundaryEntered') is False, 'MISSING_ZERO_INPUT_PROOF')
    if result=='PASS':
        evidence_path=receipt.get('acceptanceEvidencePath')
        evidence_sha=receipt.get('acceptanceEvidenceSHA256')
        need(isinstance(evidence_path,str) and isinstance(evidence_sha,str) and
             HEX.fullmatch(evidence_sha),'MISSING_ACCEPTANCE_EVIDENCE')
        evidence=Path(evidence_path)
        need(evidence.is_absolute() and evidence.is_file() and not evidence.is_symlink() and
             digest(evidence)==evidence_sha,'ACCEPTANCE_EVIDENCE_HASH_MISMATCH')
    return result,expected_digest


def recover(state,db):
    # Read only private terminal receipts already made durable by the original GUI host.
    pending=db.execute("SELECT id FROM attempts WHERE status IN ('CLAIMED','INCONCLUSIVE')").fetchall()
    for (attempt,) in pending:
        terminal=state/('terminal-'+attempt+'.json')
        if not terminal.is_file():
            if not (state/('entered-'+attempt)).exists() and owns_state(state,db):
                with locked(Path(setting(db,'guiLock'))) as fd:
                    if fd is not None and not (state/('entered-'+attempt)).exists():
                        with db:
                            db.execute("UPDATE attempts SET status='STOPPED_BEFORE_INPUT' WHERE id=?", (attempt,))
                            event(db,'RECOVERED_BEFORE_HOST_ENTRY',detail=attempt)
            continue
        try:
            claim=json.loads((state/('claim-'+attempt+'.json')).read_bytes())
            receipt=json.loads(terminal.read_bytes())
            reply=dict(receipt,receiptPath=str(terminal),receiptSHA256=digest(terminal))
            status,proof=read_result(state,claim,reply)
            with db:
                old=db.execute('SELECT status,receipt FROM attempts WHERE id=?',(attempt,)).fetchone()
                if old!=(status,proof):
                    db.execute('UPDATE attempts SET status=?,receipt=? WHERE id=?',(status,proof,attempt))
                    event(db,'RECONCILED',claim['family'],claim['case']+' '+status)
        except (OSError,ValueError,KeyError,TypeError):
            # A partial/replaced receipt cannot release a claimed file for another attempt.
            continue


def heartbeat(db, family, ok):
    with db:
        db.execute('''INSERT INTO probes VALUES(?,1,?,?)
            ON CONFLICT(family) DO UPDATE SET observations=observations+1,valid=valid+excluded.valid,last_at=excluded.last_at''',
                   (family,int(ok),now()))


def tick(state,db):
    changed=False
    recover(state,db)
    sampled={}
    for family in CASES:
        try:
            witness=sample(db,family)
            heartbeat(db,family,True)
        except (ValueError,OSError,TypeError,KeyError):
            heartbeat(db,family,False)
            _,delta=transition(db,family,{'state':'PROBE_UNAVAILABLE'})
            changed |= delta
            continue
        number,delta=transition(db,family,witness)
        changed |= delta
        sampled[family]=(witness,number)
    if len(sampled)!=len(CASES):
        return changed
    held={family for family,(witness,_) in sampled.items() if witness['heldCase']}
    if len(held)>1:
        return changed
    for family,(witness,number) in sampled.items():
        if held and family not in held:
            continue
        task=next_case(db,family,number,witness['heldCase'])
        if not task or setting(db,'armed')!='1' or setting(db,'stop')=='1' or STOP or not owns_state(state,db):
            continue
        if not (witness['ready'] or witness['preparable']):
            continue
        with locked(Path(setting(db,'guiLock'))) as fd:
            if fd is None:
                continue
            try:
                fresh=sample(db,family)
            except (ValueError,OSError,TypeError,KeyError):
                continue
            if fresh!=witness or setting(db,'armed')!='1' or setting(db,'stop')=='1' or STOP:
                continue
            nonce=secrets.token_hex(16)
            if not fresh['ready']:
                with db:
                    inserted=db.execute('INSERT OR IGNORE INTO preparations VALUES(?,?,?)',(family,task,number)).rowcount
                    if inserted:
                        event(db,'PREPARE_ON_TRANSITION',family,task)
                if not inserted:
                    continue
                try:
                    command(db,['prepare',family,task,nonce],fd,timeout=180)
                    first=sample(db,family)
                    if first.get('heldCase')!=task or not first['ready']:
                        break
                    fresh=sample(db,family)
                except (ValueError,OSError,TypeError,KeyError):
                    break
                if (fresh!=first or setting(db,'armed')!='1' or setting(db,'stop')=='1' or STOP
                        or not owns_state(state,db)):
                    break
                # A newly proven dedicated foreground target can be short-lived.
                # Still under the one GUI lease, immediately admit that exact new target.
                number,_=transition(db,family,fresh)
                if next_case(db,family,number,task)!=task:
                    break
            if db.execute("SELECT 1 FROM attempts WHERE target=? AND status IN ('CLAIMED','PASS','INCONCLUSIVE')",
                          (fresh['targetKey'],)).fetchone():
                # A different suite must get its own fresh draft. The same case
                # is also protected by the unique unresolved/positive case index.
                continue
            attempt=secrets.token_hex(16)
            claim={'attemptID':attempt,'nonce':nonce,'family':family,'case':task,'targetKey':fresh['targetKey'],
                   'environmentDigest':fresh['digest'],'source':SOURCE,'dmgSHA256':DMG,
                   'terminalPath':str(state/('terminal-'+attempt+'.json'))}
            path=state/('claim-'+attempt+'.json')
            write_private(path,claim)
            with db:
                db.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?,NULL)',(attempt,family,task,fresh['targetKey'],number,'CLAIMED'))
                event(db,'CLAIMED',family,task+' '+attempt)
            try:
                write_private(state/('entered-'+attempt),{'attemptID':attempt})
                reply=command(db,['run',family,task,nonce,str(path)],fd,timeout=3600)
                status,proof=read_result(state,claim,reply)
            except (ValueError,OSError,TypeError,KeyError):
                status,proof='INCONCLUSIVE',None
            with db:
                db.execute('UPDATE attempts SET status=?,receipt=? WHERE id=?',(status,proof,attempt))
                event(db,'RUN_RETURNED',family,task+' '+status)
            break
    return changed


def adopt(state, db, family, task, target, evidence):
    """Record a GUI-owner run begun outside this scheduler before enabling more work."""
    need(task in CASES[family] and HEX.fullmatch(target), 'INVALID_EXTERNAL_TARGET')
    evidence=evidence.resolve(strict=True)
    provenance=digest(evidence)
    with db:
        db.execute('BEGIN IMMEDIATE')
        need(setting(db,'armed')=='0', 'DISARM_BEFORE_HANDOFF')
        row=db.execute("SELECT id FROM attempts WHERE task=? AND status IN ('PASS','CLAIMED','INCONCLUSIVE')",
                       (task,)).fetchone()
        if row:
            claim_path=state/('claim-'+row[0]+'.json')
            previous=json.loads(claim_path.read_bytes())
            need(previous.get('externalEvidenceSHA256')==provenance and previous['targetKey']==target,
                 'DIFFERENT_ATTEMPT_ALREADY_RESERVED')
            return claim_path
        attempt=secrets.token_hex(16)
        claim_path=state/('claim-'+attempt+'.json')
        claim={'attemptID':attempt,'nonce':secrets.token_hex(16),'family':family,'case':task,
               'targetKey':target,'source':SOURCE,'dmgSHA256':DMG,'externalEvidenceSHA256':provenance,
               'terminalPath':str(state/('terminal-'+attempt+'.json'))}
        write_private(claim_path,claim)
        write_private(state/('entered-'+attempt),{'externalEvidenceSHA256':provenance})
        db.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?,NULL)',(attempt,family,task,target,0,'INCONCLUSIVE'))
        event(db,'EXTERNAL_OWNER_HANDOFF',family,task+' '+attempt)
    return claim_path


def terminate(_signum,_frame):
    global STOP
    STOP=True


def loop(state,db,once=False):
    with locked(state/'monitor.lock') as fd:
        need(fd is not None, 'ANOTHER_MONITOR_IS_RUNNING')
        need(setting(db,'host'), 'RUN_CONFIGURE_FIRST')
        with db:
            put(db,'monitorPID',str(os.getpid()))
            put(db,'monitorStarted',now())
            put(db,'monitorSHA',digest(Path(__file__)))
            event(db,'MONITOR_STARTED')
        delay=120
        while not STOP and setting(db,'stop')!='1':
            changed=tick(state,db)
            if once:
                break
            delay=120 if changed else min(300,delay+60)
            # Use elapsed wall time on wake. Stop checks never query the GUI.
            wall=time.time()+delay
            elapsed=time.monotonic()+delay
            while not STOP and setting(db,'stop')!='1':
                remaining=min(wall-time.time(),elapsed-time.monotonic())
                if remaining<=0:
                    break
                time.sleep(min(10,remaining))
        with db:
            event(db,'MONITOR_STOPPED')


def cli():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state',type=Path,required=True)
    sub=parser.add_subparsers(dest='action',required=True)
    config=sub.add_parser('configure')
    config.add_argument('--host',type=Path,required=True)
    config.add_argument('--gui-lock',type=Path,required=True)
    pin=sub.add_parser('update-pin')
    pin.add_argument('--host-sha256',required=True)
    pin.add_argument('--manifest-sha256',required=True)
    external=sub.add_parser('adopt')
    external.add_argument('family',choices=CASES)
    external.add_argument('case')
    external.add_argument('target_key')
    external.add_argument('evidence',type=Path)
    sub.add_parser('run').add_argument('--once',action='store_true')
    for name in ('arm','disarm','stop','resume','status','plist'):
        sub.add_parser(name)
    args=parser.parse_args()
    state=args.state.expanduser().absolute()
    os.umask(0o077)
    if args.action=='plist':
        job={'Label':'com.riftlet.qa.build60.supervisor',
             'ProgramArguments':[sys.executable,str(Path(__file__).resolve()),'--state',str(state),'run'],
             'LimitLoadToSessionType':'Aqua','RunAtLoad':True,'ThrottleInterval':120,
             'KeepAlive':{'SuccessfulExit':False}}
        sys.stdout.buffer.write(plistlib.dumps(job))
        return
    db=db_open(state)
    try:
        if args.action=='configure':
            configure(db,state,args.host,args.gui_lock)
        elif args.action=='update-pin':
            update_pin(db,args.host_sha256,args.manifest_sha256)
        elif args.action=='adopt':
            print(adopt(state,db,args.family,args.case,args.target_key,args.evidence))
        elif args.action=='run':
            signal.signal(signal.SIGTERM,terminate)
            signal.signal(signal.SIGINT,terminate)
            loop(state,db,args.once)
        elif args.action in ('arm','disarm','stop','resume'):
            need(setting(db,'host'), 'RUN_CONFIGURE_FIRST')
            if args.action=='arm':
                need(owns_state(state,db),'DURABLE_GUI_OWNER_MISMATCH')
            key='armed' if args.action in ('arm','disarm') else 'stop'
            with db:
                put(db,key,'1' if args.action in ('arm','stop') else '0')
                event(db,args.action.upper())
        else:
            with locked(state/'monitor.lock') as owner:
                running=owner is None
            gui_path=setting(db,'guiLock')
            gui_held=None
            if gui_path:
                with locked(Path(gui_path)) as gui:
                    gui_held=gui is None
            print(json.dumps({'running':running,'pid':int(setting(db,'monitorPID')) if running and setting(db,'monitorPID') else None,
                              'monitorStarted':setting(db,'monitorStarted'),'monitorSHA256':setting(db,'monitorSHA'),
                              'guiLeaseHeld':gui_held,'probes':list(db.execute('SELECT * FROM probes ORDER BY family')),
                              'armed':setting(db,'armed')=='1','stopRequested':setting(db,'stop')=='1',
                              'hostSHA256':setting(db,'hostSHA'),'hostManifestSHA256':setting(db,'manifestSHA'),'samples':[(f,json.loads(s),n) for f,s,n in db.execute('SELECT * FROM samples')],
                              'attempts':list(db.execute('SELECT family,task,status,receipt FROM attempts ORDER BY rowid')),
                              'recentEvents':list(db.execute('SELECT at,kind,family,detail FROM events ORDER BY id DESC LIMIT 10'))},indent=2))
    finally:
        db.close()


if __name__=='__main__':
    try:
        cli()
    except (ValueError,OSError,sqlite3.Error) as error:
        print(str(error),file=sys.stderr)
        sys.exit(1)
