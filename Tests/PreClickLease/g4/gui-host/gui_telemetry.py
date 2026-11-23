"""Local, transition-only metadata for the actual calling context. Never visits a web page."""
from datetime import datetime,timezone
import hashlib,json,os,re,sqlite3,subprocess

def observer_context():
    uid=os.getuid()
    if os.getppid()<=1:return 'OTHER_PROCESS'
    p=subprocess.run(['/bin/launchctl','print',f'gui/{uid}/com.riftlet.qa.build60.supervisor'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=4,text=True)
    # Extract only the numeric PID of our explicitly named QA job. Do not
    # persist its environment, service graph, arguments or other private text.
    match=re.search(r'^\s*pid = ([1-9][0-9]*)\s*$',p.stdout,flags=re.MULTILINE)
    return 'REGISTERED_AQUA_SUPERVISOR' if p.returncode==0 and match and int(match.group(1))==os.getppid() else 'OTHER_PROCESS'

def failure_code(env,family,checks,reason,held):
    browser=env.get('browsers',{}).get(family,{})
    if not env.get('onConsole') or not env.get('loginDone'):return 'NO_ACTIVE_USER_CONSOLE'
    if env.get('screenLocked') or not env.get('displayAwake'):return 'LOCKED_OR_ASLEEP'
    if env.get('protectedForeground') or env.get('systemDialogOnScreen') or env.get('frontHasModal'):return 'PROTECTED_OR_MODAL_SURFACE'
    if not env.get('axTrusted'):return 'ACCESSIBILITY_NOT_TRUSTED'
    if not browser.get('running'):return 'ORIGINAL_VENDOR_PROCESS_UNAVAILABLE'
    ae=browser.get('aePermission')
    if ae in ('DENIED','CONSENT_REQUIRED','UNKNOWN_OS_STATUS','TARGET_NOT_RUNNING','TARGET_UNAVAILABLE'):
        return 'APPLE_EVENTS_'+ae
    if not held:return 'NO_HELD_SCOPE'
    if reason:
        if reason in ('APPLE_EVENT_DENIED','APPLE_EVENT_CONSENT_REQUIRED','ORIGINAL_ROUTE_CHANGED','BROWSER_APPLE_EVENT_JAVASCRIPT_DISABLED','AE_PERMISSION_NOT_ESTABLISHED_WITHOUT_PROMPT'):return reason
        return 'ORIGINAL_OBSERVATION_UNAVAILABLE'
    if not checks.get('nativeForeground'):return 'ORIGINAL_BROWSER_NOT_FOREGROUND'
    if not checks.get('cgWindowOnScreen'):return 'ORIGINAL_CG_SURFACE_UNCONFIRMED'
    if not checks.get('axOriginalWindow'):return 'ORIGINAL_AX_WINDOW_UNCONFIRMED'
    if not all(checks.values()):return 'ORIGINAL_DOCUMENT_OR_BROWSER_GATE_UNSATISFIED'
    return 'READY'

def journal(base,family,env,checks,reason,held,manager,target,context=None):
    context=context or observer_context()
    # Store each actual transition, per observed browser and launch context.
    # Never carry URLs, titles, button labels, page text, or notification contents.
    docs=[]
    for a in env.get('frontAX',[]):
        docs.append({k:a[k] for k in ('role','subrole','modal','bounds') if k in a})
    browsers={f:{k:v[k] for k in ('running','regular','hidden','active','axWindowCount','cgBaseWindowCount','cgOnScreenCount','axWindowAttributeReadable','aePermission','queryWithoutPrompt') if k in v} for f,v in env.get('browsers',{}).items()}
    protected=[]
    for item in env.get('protectedSystemSurfaces',[]):
        protected.append({'bundle':item.get('bundle'),'pid':item.get('pid'),
          'ax':[{k:r[k] for k in ('role','subrole','modal','bounds') if k in r} for r in item.get('ax',[])],
          'cg':[{k:r[k] for k in ('layer','bounds') if k in r} for r in item.get('cg',[])]})
    data={'context':context,'family':family,'launchManager':manager,'frontPID':env.get('frontPID'),
          'frontBundle':env.get('frontBundle'),'frontWindowMetadata':docs,
          'protectedSystemWindows':protected,
          'systemDialogOnScreen':env.get('systemDialogOnScreen'),'protectedForeground':env.get('protectedForeground'),
          'frontHasModal':env.get('frontHasModal'),'displayAwake':env.get('displayAwake'),'screenLocked':env.get('screenLocked'),
          'onConsole':env.get('onConsole'),'loginDone':env.get('loginDone'),'consoleUIDMatches':env.get('consoleUIDMatches'),
          'axTrusted':env.get('axTrusted'),'displays':env.get('displays',[]),'browsers':browsers,'checks':checks,
          'heldScope':bool(held),'targetSHA256':target,'failure':failure_code(env,family,checks,reason,held)}
    if reason in ('APPLE_EVENT_DENIED','APPLE_EVENT_CONSENT_REQUIRED','BROWSER_APPLE_EVENT_JAVASCRIPT_DISABLED','AE_PERMISSION_NOT_ESTABLISHED_WITHOUT_PROMPT'):data['originalReadRefusal']=reason
    payload=json.dumps(data,sort_keys=True,separators=(',',':'));key=hashlib.sha256(payload.encode()).hexdigest()
    path=base/'host-observations.sqlite'
    db=sqlite3.connect(path,timeout=4)
    try:
        db.execute('BEGIN IMMEDIATE')
        db.execute('CREATE TABLE IF NOT EXISTS transitions(id INTEGER PRIMARY KEY, received_utc TEXT NOT NULL, context TEXT NOT NULL, family TEXT NOT NULL, digest TEXT NOT NULL, metadata TEXT NOT NULL)')
        last=db.execute('SELECT digest FROM transitions WHERE context=? AND family=? ORDER BY id DESC LIMIT 1',(context,family)).fetchone()
        if not last or last[0]!=key:
            db.execute('INSERT INTO transitions(received_utc,context,family,digest,metadata) VALUES(?,?,?,?,?)',(datetime.now(timezone.utc).isoformat(),context,family,key,payload))
        db.commit()
    finally:db.close()
    os.chmod(path,0o600)
