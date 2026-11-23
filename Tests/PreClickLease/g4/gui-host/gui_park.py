"""Preserve a completed emitter's original target as read-only without retrying it or closing its window."""
import hashlib
import json
import os
from pathlib import Path
import re
import uuid

def read(path):
    return json.loads(path.read_bytes())
def require(ok):
    if not ok:raise ValueError('PARKING_EVIDENCE_MISMATCH')
def hash_file(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def proposal(base,scope,receipt=None):
    """No actions and no writes. Return a transition only for a proven prior product file input."""
    if scope.get('case') not in ('g4c','b4') or scope.get('family')!='edge':return None
    root=Path(scope['root'])
    require(root.is_dir() and root.parent==base and root.resolve()==root)
    state=root/'signed60/edge'
    issued=root/'business-claim.json'
    if not issued.is_file() or (state/'closed.json').exists():return None
    bound=read(issued)
    require(bound['case']==scope['case'] and bound['family']==scope['family'] and re.fullmatch('[a-f0-9]{32}',bound['attemptID']) and re.fullmatch('[a-f0-9]{64}',bound['targetKey']))
    owner=read(base/'build60-supervisor-owner.json')
    expected_state=Path(owner['state'])
    require(expected_state.resolve()==expected_state and expected_state.is_dir() and owner['dmgSHA256']==bound['dmgSHA256'])
    expected_path=expected_state/('terminal-'+bound['attemptID']+'.json')
    if receipt is not None:require(Path(receipt)==expected_path)
    if not expected_path.is_file():return None
    require(not expected_path.is_symlink() and expected_path.stat().st_uid==os.getuid())
    terminal=read(expected_path)
    require(all(bound.get(k)==terminal.get(k) for k in ['attemptID','nonce','family','case','targetKey','dmgSHA256']))
    if terminal.get('outcome')!='INCONCLUSIVE':return None
    business=state/('live-g4-transport' if scope['case']=='g4c' else 'live-size-60')
    files={k:business/(k+'.json') for k in ('result','child','final-page','final-db')}
    if not all(p.is_file() and not p.is_symlink() for p in files.values()):return None
    result,child,page,db=(read(files[k]) for k in ('result','child','final-page','final-db'))
    if terminal.get('acceptanceEvidencePath'):
        report=Path(terminal['acceptanceEvidencePath'])
        require(report.resolve()==report and report.parent==business and hash_file(report)==terminal['acceptanceEvidenceSHA256'])
    count=page.get('counts',{});n=count.get('fileInput')
    if type(n)!=int or n<1:return None
    require(count.get('fileChange')==n and count.get('sendButtonClicks')==0 and count.get('formSubmit')==0)
    require(page.get('originalDocument') is True and page.get('originalEditor') is True)
    operations=db.get('operations',[]);require(operations and all(isinstance(x.get('id'),str) for x in operations))
    profile=str(uuid.UUID(child['profile']));require(profile==child['profile'] and child['candidate']['sha256']==bound['dmgSHA256'])
    require(type(child['pid'])==int and child['pid']>1)
    before=read(state/'before.json');created=read(state/'creation.json');entry=read(state/'original-entry.json')
    require(created['phase']=='qaAddressConfirmed' and created['sessionID']==before['sessionID'] and created['windowID'] not in before['windowIDs'])
    original=[created['sessionID'],created['windowID'],created['tabID'],entry['entryID'],entry['timeOrigin'],entry['sourceDoc'],bound['dmgSHA256']]
    require(hashlib.sha256(json.dumps(original,sort_keys=True,separators=(',',':')).encode()).hexdigest()==bound['targetKey'])
    handoff=business/'observation-handoff.json'
    if result.get('privateChildExited') is not True:
        if not handoff.is_file() or result.get('resumeMode')!='ORIGINAL_READ_ONLY':return None
        h=read(handoff)
        require(h.get('noReplay') is True and h.get('issued') is True and h.get('profile')==profile and h.get('pid')==child['pid'])
        files['observationHandoff']=handoff
    return {'schema':1,'mode':'ORIGINAL_READ_ONLY_NO_DISPATCH','attemptID':bound['attemptID'],'family':scope['family'],
            'case':scope['case'],'targetKey':bound['targetKey'],'dmgSHA256':bound['dmgSHA256'],'originalScope':str(root),
            'originalWindowID':created['windowID'],'originalTabID':created['tabID'],'originalBrowserBirth':created['sessionID'],
            'originalEntryID':entry['entryID'],'originalTimeOrigin':entry['timeOrigin'],'originalChildPID':child['pid'],
            'originalPrivateProfile':profile,'originalPrivateChildExited':result.get('privateChildExited') is True,'inputEvents':n,
            'changeEvents':n,'operations':len(operations),'terminalReceiptSHA256':hash_file(expected_path),
            'sourceReceipts':{k:hash_file(p) for k,p in files.items()},'originalWindowClosedByParking':False}
def logical(base,scope):
    try:return proposal(base,scope)
    except (KeyError,ValueError,TypeError,OSError):return None
def install(base,scope,manifest,write_new):
    """Caller owns gui.lock. Journal before unlinking active. Recover a partially finished transition."""
    active=base/'active-scope.json'
    require(read(active)==scope)
    current=proposal(base,scope)
    require(current==manifest)
    idx=base/'parked';idx.mkdir(mode=0o700,exist_ok=True)
    path=idx/(manifest['attemptID']+'.json')
    try:write_new(path,manifest)
    except FileExistsError:require(read(path)==manifest)
    source=Path(scope['root'])/'preserved-scope.json'
    try:os.link(active,source)
    except FileExistsError:require(source.is_file() and not source.is_symlink() and os.path.samefile(active,source))
    require(os.path.samefile(source,active) and read(source)==scope)
    active.unlink();d=os.open(base,os.O_RDONLY)
    try:os.fsync(d)
    finally:os.close(d)
    return path
def excludes(base,task=None,target=None):
    directory=base/'parked'
    if not directory.exists():return False
    for p in directory.glob('*.json'):
        j=read(p)
        require(j['mode']=='ORIGINAL_READ_ONLY_NO_DISPATCH' and p.stem==j['attemptID'])
        if (task and j['case']==task) or (target and j['targetKey']==target):return True
    return False
