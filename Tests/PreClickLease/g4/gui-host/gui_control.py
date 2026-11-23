"""Lease-based private macOS GUI runner. All mutations need the supervisor's actual GUI flock."""
import contextlib
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
from gui_sample import command, read, sample
import gui_park

CASES={'chrome':{'g1'},'edge':{'g2','g4c','b4'}}
PROTECTED=('com.apple.UserNotificationCenter','com.apple.SecurityAgent','com.apple.CoreAuthUI','com.apple.loginwindow')
def need(ok,message):
    if not ok:raise ValueError(message)
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def write_new(path,value):
    # Link a complete, fsynced temporary file exclusively and fsync the directory.
    data=(json.dumps(value,sort_keys=True,indent=2)+'\n').encode()
    fd,name=tempfile.mkstemp(dir=path.parent,prefix='.sealed-',suffix='.tmp')
    try:
        with os.fdopen(fd,'wb') as stream:
            stream.write(data);stream.flush();os.fsync(stream.fileno())
        os.link(name,path)
        d=os.open(path.parent,os.O_RDONLY)
        try:os.fsync(d)
        finally:os.close(d)
    finally:Path(name).unlink(missing_ok=True)
@contextlib.contextmanager
def lease(base):
    expected=base/'gui.lock'
    need(os.environ.get('RIFTLET_GUI_LOCK_PATH')==str(expected),'ORIGINAL_GUI_FLOCK_REQUIRED')
    fd=int(os.environ['RIFTLET_GUI_LOCK_FD']);need(os.path.samestat(os.stat(expected),os.fstat(fd)),'WRONG_GUI_FD')
    fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
    yield fd
def root_of(base,scope,family,task):
    path=Path(scope['root'])
    need(path.parent==base and path.resolve()==path and scope['family']==family and scope['case']==task,'ACTIVE_SCOPE_MISMATCH')
    return path,path/'signed60'/family
def execute_file(script,*args,logdir,tag,fd):
    with (logdir/(tag+'.stdout')).open('xb') as stdout,(logdir/(tag+'.stderr')).open('xb') as stderr:
        # Even if the host dies, the runner keeps the same open flock until it exits.
        return subprocess.run([sys.executable,'-B',script,*args],stdin=subprocess.DEVNULL,stdout=stdout,stderr=stderr,pass_fds=(fd,)).returncode
def implementation(site):
    sys.path.insert(0,str(site))
    import run as coordinator
    from candidate import installed
    installed()
    return coordinator
def present_held(base,site,family,task,nonce):
    env=command([Path(__file__).resolve().parent/'window-evidence','environment'])
    need(env['eligibleForPreparation'] and env['browsers'].get(family,{}).get('aePermission')=='ALLOWED','DESKTOP_OR_BROWSER_AUTHORIZATION_UNAVAILABLE')
    scope=read(base/'active-scope.json');root,state=root_of(base,scope,family,task)
    need((state/'ready60.json').is_file() and not (state/'closed.json').exists(),'NO_PREVIOUSLY_VERIFIED_ORIGINAL_DRAFT')
    prepared=base/('presentation-'+nonce+'.json')
    write_new(base/('presentation-intent-'+nonce+'.json'),{'case':task,'source':scope['root']})
    if sample(base,site,family,nonce)['ready']:
        write_new(prepared,{'alreadyReady':True});return
    result=command([Path(__file__).resolve().parent/'present-original',state,family],limit=12)
    write_new(prepared,result)
    need(result['originalSelected'] and result['systemForeground'],'ORIGINAL_NOT_PRESENTED')
def prepare(base,site,family,task,nonce,fd):
    coord=implementation(site);scope_file=base/'active-scope.json'
    if scope_file.exists():
        existing=read(scope_file); proposed=gui_park.logical(base,existing)
        if proposed:gui_park.install(base,existing,proposed,write_new)
    need(not gui_park.excludes(base,task=task),'PARKED_CASE_IS_READ_ONLY')
    if scope_file.exists():
        scope=read(scope_file);root,state=root_of(base,scope,family,task)
        need(not any(state.glob('live-*')) and not (root/'business-claim.json').exists(),'ORIGINAL_OPERATION_REQUIRES_OBSERVATION')
        present_held(base,site,family,task,nonce)
    else:
        need(task!='g4c','G4C_ISSUER_HAS_SEPARATELY_PINNED_ORIGINAL_SCOPE')
        env=command([Path(__file__).resolve().parent/'window-evidence','environment'])
        need(env['eligibleForPreparation'] and env['browsers'].get(family,{}).get('aePermission')=='ALLOWED','DESKTOP_OR_BROWSER_AUTHORIZATION_UNAVAILABLE')
        root=base/(task+'-'+nonce);state=root/'signed60'/family
        need(not root.exists(),'FRESH_SCOPE_REQUIRED')
        write_new(scope_file,{'family':family,'case':task,'root':str(root),'entry':'new-sole-verified-native-window','preInput':True})
        coord.folder=lambda a:(root,state) if a.root==root and a.family==family else (_ for _ in ()).throw(ValueError('WRONG_NEW_SCOPE'))
        spec=importlib.util.spec_from_file_location('servedDocument',site/'prepare-document.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        module.prepare(SimpleNamespace(family=family,root=root))
    p=sample(base,site,family,nonce)
    return {'family':family,'case':task,'nonce':nonce,'targetKey':p['targetKey'],'ready':p['ready']}
def strict_claim(claimPath,family,task,nonce,source):
    need(claimPath.is_absolute() and claimPath.resolve(strict=True)==claimPath and claimPath.stat().st_uid==os.getuid(),'INVALID_PRIVATE_CLAIM')
    j=read(claimPath);aid=j['attemptID']
    need(re.fullmatch('[0-9a-f]{32}',aid) and claimPath.name=='claim-'+aid+'.json' and j['nonce']==nonce and j['family']==family and j['case']==task and j['source']==source['source'] and j['dmgSHA256']==source['dmgSHA256'],'WRONG_ATTEMPT')
    need(re.fullmatch('[a-f0-9]{64}',j['targetKey']) and re.fullmatch('[a-f0-9]{64}',j['environmentDigest']),'MISSING_ORIGINAL_TARGET')
    end=claimPath.with_name('terminal-'+aid+'.json')
    need(j['terminalPath']==str(end),'WRONG_TERMINAL_PATH')
    return j,end
def returned(terminal,row):
    return dict(row,receiptPath=str(terminal),receiptSHA256=sha(terminal))
def retire_active(base,scope,state,coordinator):
    root=state.parent.parent
    coordinator.folder=lambda a:(root,state) if a.root==root and a.family==scope['family'] else (_ for _ in ()).throw(ValueError('WRONG_SCOPE'))
    coordinator.close(SimpleNamespace(root=root,family=scope['family']))
    closed=read(state/'closed.json');need(closed['closeRequests']==1 and closed['windowClosed'],'ORIGINAL_NOT_CLOSED')
    source=base/'active-scope.json'
    need(read(source)==scope,'ACTIVE_SCOPE_CHANGED')
    os.rename(source,root/'closed-scope.json')
def run_case(base,site,g4driver,family,task,nonce,claimPath,fd):
    coord=implementation(site)
    j,terminal=strict_claim(claimPath,family,task,nonce,read(base/'candidate.json'))
    prefix={k:j[k] for k in ('attemptID','nonce','family','case','targetKey','dmgSHA256')}
    if terminal.exists():
        done=read(terminal);need(all(done.get(k)==v for k,v in prefix.items()),'MISMATCHED_PREVIOUS_RESULT');return returned(terminal,done)
    need(not gui_park.excludes(base,task=task,target=j['targetKey']),'PARKED_ORIGINAL_IS_READ_ONLY')
    scope=read(base/'active-scope.json');root,state=root_of(base,scope,family,task)
    lane=root/('admission-'+j['attemptID']);lane.mkdir(mode=0o700)
    receipts=[]
    for i in (1,2):
        p=sample(base,site,family,nonce,lambda raw:write_new(lane/('native-'+str(i)+'.json'),raw))
        write_new(lane/('gate-'+str(i)+'.json'),p);receipts.append(p)
    if not all(p['ready'] and p['targetKey']==j['targetKey'] and p['digest']==j['environmentDigest'] and p['heldCase']==task for p in receipts):
        stop=dict(prefix,outcome='STOPPED_BEFORE_INPUT',productInputCount=0,inputBoundaryEntered=False)
        write_new(terminal,stop);return returned(terminal,stop)
    need(not (root/'g4c-live-intent.json').exists() and not any(state.glob('live-*')) and not (root/'business-claim.json').exists(),'NO_SECOND_DISPATCH_TO_EXISTING_DRAFT')
    write_new(root/'business-claim.json',dict(prefix,source=j['source'],originalAdmission=[sha(lane/f'gate-{i}.json') for i in (1,2)]))
    if task=='g4c':
        need(state==base/'g4c-first/signed60/edge','G4C_PINNED_ORIGINAL_STATE_REQUIRED')
        tools=g4driver/'final/tools.json';need(sha(tools)=='f4f1dfdb4bfd776b9d24d9fb426891b90b374d567f818a77eb9b29aa1a6d2afd','G4C_TOOL_MANIFEST_CHANGED')
        for n,h in read(tools).items():need(sha(Path(n))==h,'G4C_TOOL_CHANGED')
        script,args,business=g4driver/'live.py',[family,'--state',str(state)],state/'live-g4-transport'
    elif task=='b4':
        script,args,business=site/'size_round.py',[family,'--state',str(state)],state/'live-size-60'
    else:
        script,args,business=site/'live_round.py',[family,'--combined','--state',str(state)],state/'live-final-round'
    rc=execute_file(script,*args,logdir=lane,tag='real-site',fd=fd)
    result=business/'result.json'
    product=read(result) if result.exists() else {}
    okay=False;archive=result;extra={}
    if task in ('g1','g2') and product.get('status')=='REQUESTED_CASES_OBSERVED':
        audit=execute_file(site/'audit_round.py',str(business),logdir=lane,tag='audit',fd=fd)
        if audit==0:
            archive=lane/'audit.stdout';derived=read(archive)
            okay=(derived.get('rapid',{}).get('status')=='RAPID_PAIRS_PASS' and derived.get('selection',{}).get('textAndSelection')=='PASS' and product.get('rapid')=='PASS' and product.get('selection')=='PASS')
            initial=read(business/'page-before-1.json')
            warm=read(business/'cards-before-2.json')
            seed=read(business/'positive-1.json')[0]
            second=read(business/'positive-3.json')[0]
            cold=(initial['counts']['fileInput']==0 and not initial['files'] and seed['index']==1)
            warm_first=(warm['counts']['fileInput']==1 and len(warm['files'])==1 and second['index']==2 and second['sha256']!=seed['sha256'])
            extra['coldFirstConfirmed']=cold
            extra['warmFirstConfirmed']=warm_first
            extra['warmFirstIsFirstImageOfFirstRapidPair']=True
            okay=okay and cold and warm_first
    elif task=='g4c':
        okay=product.get('status')=='G4_C_OBSERVED' and (business/'durable-recovery.json').is_file() and (business/'final-db.json').is_file()
        if okay:archive=business/'durable-recovery.json'
    elif task=='b4':
        # The size experiment is complete once observed. Upstream 4xx and G4-B must be independently proved.
        extra['siteSizeObservation']=product.get('status','NOT_OBSERVED')
        extra['positiveNamedFailureCard']=product.get('b4',{}).get('positiveNamedFailureCard') is True
    extra['runnerExit']=rc
    done=dict(prefix,outcome='PASS' if okay else 'INCONCLUSIVE',**extra)
    if archive.is_file():done.update(acceptanceEvidencePath=str(archive),acceptanceEvidenceSHA256=sha(archive))
    write_new(terminal,done)
    # An unresolved original, or a retained named failure, stays available for independent, read-only review.
    safe_close=(product.get('privateChildExited') is True and not product.get('leaveOriginalWatcherForIndependentRecovery') and product.get('resumeMode')!='ORIGINAL_READ_ONLY')
    parked=gui_park.logical(base,scope) if done['outcome']=='INCONCLUSIVE' else None
    if parked:
        gui_park.install(base,scope,parked,write_new)
    elif safe_close:
        try:retire_active(base,scope,state,coord)
        except (RuntimeError,ValueError,OSError,KeyError,subprocess.SubprocessError):
            write_new(lane/'close-needs-owned-review.json',{'reason':'EXACT_SCOPE_CLEANUP_INCOMPLETE'})
    return returned(terminal,done)
def action(base,site,g4driver,argv):
    op,family,task,nonce,*tail=argv
    need(task in CASES.get(family,set()) and re.fullmatch(r'[a-zA-Z0-9_-]{1,160}',nonce),'INVALID_CASE')
    with lease(base) as fd:
        if op=='prepare' and not tail:return prepare(base,site,family,task,nonce,fd)
        if op=='run' and len(tail)==1:return run_case(base,site,g4driver,family,task,nonce,Path(tail[0]),fd)
        raise ValueError('UNKNOWN_GUI_ACTION')
