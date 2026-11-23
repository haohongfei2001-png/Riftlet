"""Verify two existing signed original-process inventories and preserve their hashes. No browser operations."""
from pathlib import Path
import hashlib, os
from lanes import read, root_of, issued, check
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def verify(base,row,folder,*,historical=False):
    root=root_of(base,row);f=row['family'];state=root/'signed61'/f;created=read(state/'creation.json')
    before=read(state/'before.json');scope=read(root/'candidate-scope.json')
    check(scope['dmgSHA256']==read(base/'candidate.json')['dmgSHA256'] and created['family']==f and
          created['phase']=='qaAddressConfirmed' and created['sessionID']==before['sessionID'] and created['pid']==before['pid'] and
          str(created['windowID']) not in list(map(str,before['windowIDs'])),'ORIGINAL_CREATION_REQUIRED')
    check(not issued(base,row),'PREVIOUS_BUSINESS_OR_NETWORK_MAY_HAVE_STARTED')
    for p in (base/'execution').glob('claim-*.json'):
        j=read(p)
        check(historical or j['case']!=row['case'],'PRIOR_DURABLE_CLAIM_REQUIRES_ORIGINAL')
    ps=[folder/(f+'-inventory-'+str(i)+'.json') for i in (1,2)]
    check(folder.resolve()==folder and len({p.stat().st_ino for p in ps})==2 and
          ps[1].stat().st_mtime_ns>ps[0].stat().st_mtime_ns>=(state/'creation.json').stat().st_mtime_ns,'TWO_ORDERED_ORIGINAL_PROCESS_INVENTORIES_REQUIRED')
    for p in ps:
        check(p.resolve()==p and p.stat().st_uid==os.getuid(),'UNOWNED_NATIVE_RECEIPT')
        packet=read(p);r=packet['json']
        check(type(packet['code']) is int and packet['code']==0 and r['family']==f and r['dynamicSignature'] is True and
              all(r[k]==before[k] for k in ('family','pid','sessionID','bundle','teamID','executable','bundlePath','developerIDRequirement')) and
              isinstance(r['windowIDs'],list) and str(created['windowID']) not in list(map(str,r['windowIDs'])),'ORIGINAL_MUST_BE_ABSENT_TWICE')
    return {'status':'ORIGINAL_WINDOW_GONE_BEFORE_BUSINESS','family':f,'case':row['case'],'scope':str(root),
            'digest':scope['dmgSHA256'],'creationSHA256':sha(state/'creation.json'),'inventoryPaths':[str(p) for p in ps],
            'inventorySHA256':[sha(p) for p in ps],'businessMayHaveStarted':False}
def attested(base,row):
    p=root_of(base,row)/'external-disappearance-before-input.json'
    if not p.exists():return False
    check(p.resolve()==p,'UNSAFE_RETIREMENT')
    old=read(p);folder=Path(old['inventoryPaths'][0]).parent
    # Subsequent business on a different scope consumes the shared case, but does not invalidate this old retirement.
    # All issued-guards still run independently in handled() before scheduling any new work.
    check(verify(base,row,folder,historical=True)==old,'CHANGED_DISAPPEARANCE_ATTESTATION')
    return True
def attest_under_flock(base,row,folder,write_new):
    from gui_control import lease
    with lease(base):
        result=verify(base,row,folder)
        dest=root_of(base,row)/'external-disappearance-before-input.json'
        if not dest.exists():write_new(dest,result)
        check(read(dest)==result,'CHANGED_PRIOR_RETIREMENT')
        return result
