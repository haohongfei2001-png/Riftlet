"""Per-family planning; all state reads and actions below are under the same real GUI lease."""
import json,re,sqlite3,subprocess,time,uuid
from pathlib import Path
import lanes

def handled(path,source,dmg):
    tasks={};targets=set()
    for f in sorted(path.glob('claim-*.json')):
        a=lanes.read(f);aid=a['attemptID'];k=a['case']
        lanes.known(a['family'],k)
        lanes.check(f.resolve()==f and re.fullmatch('[0-9a-f]{32}',aid) and f.name=='claim-'+aid+'.json' and
                    a['source']==source and a['dmgSHA256']==dmg and re.fullmatch('[0-9a-f]{64}',a['targetKey']) and
                    a['terminalPath']==str(path/('terminal-'+aid+'.json')),'UNKNOWN_DURABLE_CLAIM')
        t=Path(a['terminalPath'])
        status='UNRESOLVED_ORIGINAL_ONLY'
        if t.exists():
            lanes.check(t.resolve()==t,'UNSAFE_TERMINAL');r=lanes.read(t)
            lanes.check(all(a[v]==r[v] for v in ('family','case','targetKey','dmgSHA256','attemptID','nonce')),'MISMATCHED_DURABLE_TERMINAL')
            if r.get('outcome')=='STOPPED_BEFORE_INPUT' and type(r.get('productInputCount')) is int and r['productInputCount']==0 and r.get('inputBoundaryEntered') is False:
                continue
            status=r['outcome']
        targets.add(a['targetKey']);tasks[k]=status
    for f,ks in lanes.FAMILIES.items():
        for k in ks:
            try:
                indexed=lanes.history(path.parent,f,k)
                lanes.check(sum(not lanes.finished(path.parent,row) for row in indexed)<=1,'MULTIPLE_UNCLOSED_ORIGINAL_SCOPES')
                registered={lanes.root_of(path.parent,row) for row in indexed}
                for state in path.parent.glob(k+'-*/signed61/'+f):
                    r=state.parent.parent
                    if r not in registered and ((r/'business-claim.json').is_file() or (r/'g4c-live-intent.json').is_file() or any(state.glob('live-*'))):
                        tasks.setdefault(k,'ISSUED_ORIGINAL_ONLY')
                for row in indexed:
                    if lanes.issued(path.parent,row):
                        tasks.setdefault(k,'ISSUED_ORIGINAL_ONLY')
                        p=lanes.root_of(path.parent,row)/'business-claim.json'
                        if p.exists():targets.add(lanes.read(p)['targetKey'])
            except (ValueError,KeyError,TypeError,OSError):
                tasks[k]='ORIGINAL_LANE_REVIEW_REQUIRED'
    return tasks,targets

def cycle(module,db,agenda,source,dmg):
    base,site,host=module.BASE,module.SITE,module.host
    private=base/'execution'
    with module.claim_gui() as fd:
        if fd is None:return {'state':'GUI_HELD_BY_OTHER_OWNER'}
        lanes.init(db);lanes.snapshot_pointer(base,host.write_new)
        previous,used=handled(private,source,dmg)
        nonce=uuid.uuid4().hex;items=[];gates={}
        for f,k in agenda:
            if k in previous:continue
            try:
                row=lanes.original(base,f,k)
                s=module.sample(base,site,f,nonce,scope=row)
            except (ValueError,RuntimeError,OSError,KeyError,sqlite3.Error,subprocess.SubprocessError):
                gates[f+'/'+k]={'sample':'unavailable'};continue
            e=lanes.observe(db,f,k,s)
            gates[f+'/'+k]={'eligible':s['environment']['eligibleForPreparation'],'ready':s['ready'],'held':s['heldCase'],
                            'protected':s['environment']['protectedForeground'] or s['environment']['systemDialogOnScreen']}
            items.append((f,k,s,e))
        with db:
            db.execute('INSERT INTO ticks(utc,sampled,ready,protected) VALUES(?,?,?,?)',(time.time(),len(items),sum(s['ready'] for _,_,s,_ in items),sum(v.get('protected',False) for v in gates.values())))
        if not any(k not in previous for _,k in agenda):
            if any(previous.get(k) in ('UNRESOLVED_ORIGINAL_ONLY','ISSUED_ORIGINAL_ONLY','ORIGINAL_LANE_REVIEW_REQUIRED') for _,k in agenda):
                return {'state':'WAITING_FOR_ORIGINAL_TERMINAL','results':previous}
            return {'state':'DISPATCH_TERMINAL','results':previous}
        options=lanes.eligible_order(db,items,time.time())
        if not options:return {'state':'WAITING_ON_ORIGINAL_ENVIRONMENT','gates':gates,'completedOrUndecided':previous}
        fam,task,s,epoch=options[0]
        held=lanes.original(base,fam,task)
        # Legacy runner internals consult this pointer. Everything addressable through it is independently indexed.
        lanes.point(base,held,host.write_new)
        lanes.attempted(db,fam,task,epoch,s,'SELECTED_BEFORE_INPUT')
        if not s['ready'] or not held or not (Path(held['root'])/'signed61'/fam/'ready61.json').is_file():
            host.write_new(private/('prepare-'+nonce+'.json'),{'nonce':nonce,'family':fam,'case':task,'transition':epoch,'digest':s['digest'],'readyBefore':s['ready'],'utc':time.time()})
            try:host.action(base,site,module.G4,['prepare',fam,task,nonce])
            except (ValueError,RuntimeError,OSError,KeyError,LookupError,subprocess.SubprocessError) as ex:
                code=str(ex);code=code if re.fullmatch('[A-Z0-9_]{1,130}',code) else type(ex).__name__
                host.write_new(private/('prepare-stop-'+nonce+'.json'),{'family':fam,'case':task,'reason':code,'productInputCount':0})
                return {'state':'PREPARED_STOPPED_BEFORE_INPUT','family':fam,'case':task,'reason':code,'gates':gates}
            finally:lanes.snapshot_pointer(base,host.write_new)
        owned=lanes.original(base,fam,task)
        lanes.check(owned and lanes.read(base/'active-scope.json')==owned,'ORIGINAL_INDEX_CHANGED')
        try:two=[module.sample(base,site,fam,nonce,scope=owned) for _ in range(2)]
        except (ValueError,RuntimeError,OSError,KeyError,sqlite3.Error,subprocess.SubprocessError):
            return {'state':'ORIGINAL_SAMPLE_UNAVAILABLE','family':fam,'case':task,'gates':gates}
        p=two[0]
        from gui_sample import CHECKS
        if not all(x['ready'] is True and all(x['checks'].get(i) is True for i in CHECKS) and x['family']==fam and x['nonce']==nonce and
                   x['heldCase']==task and x.get('identityProof') and x['identityProof']==p['identityProof'] and
                   x['identityProof']['nativeRouteSHA256']==x['targetKey'] and re.fullmatch('[0-9a-f]{64}',x['targetKey']) and
                   x['targetKey']==p['targetKey'] and x['digest']==p['digest'] for x in two):
            return {'state':'ORIGINAL_REQUIRED','family':fam,'case':task,'gates':gates}
        lanes.check((Path(owned['root'])/'signed61'/fam/'ready61.json').is_file(),'TWO_GATES_ON_FRESH_CANDIDATE_DRAFT_REQUIRED')
        existing,used=handled(private,source,dmg)
        lanes.check(task not in existing and p['targetKey'] not in used,'ORIGINAL_ALREADY_CONSUMED')
        aid=uuid.uuid4().hex
        claim=dict(attemptID=aid,nonce=nonce,family=fam,case=task,targetKey=p['targetKey'],environmentDigest=p['digest'],
                   source=source,dmgSHA256=dmg,originalProof=p['identityProof'],terminalPath=str(private/('terminal-'+aid+'.json')))
        dest=private/('claim-'+aid+'.json');host.write_new(dest,claim)
        try:done=host.action(base,site,module.G4,['run',fam,task,nonce,str(dest)])
        except (ValueError,RuntimeError,OSError,KeyError,sqlite3.Error,subprocess.SubprocessError):
            return {'state':'CLAIM_RETAINED_ORIGINAL_ONLY','family':fam,'case':task}
        return {'state':'CASE_OBSERVED','family':fam,'case':task,'outcome':done['outcome'],'terminalSHA256':done['receiptSHA256']}
