"""Obtain fresh, metadata-only GUI and original-draft receipts in a sealed private deployment."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from gui_park import logical
from gui_telemetry import journal

CHECKS = ('nativeForeground', 'nativeWindowVisible', 'cgWindowOnScreen', 'axOriginalWindow',
          'originalTabSelected', 'documentVisible', 'documentFocused', 'signedIn',
          'composer', 'uploadEntry', 'dedicatedSingleTab', 'originalProcessBirth')
def digest(value):
    raw = json.dumps(value, sort_keys=True, separators=(',', ':')).encode()
    return hashlib.sha256(raw).hexdigest()
def read(path):
    return json.loads(path.read_bytes())
def command(args, limit=8):
    p = subprocess.run([str(a) for a in args], capture_output=True, timeout=limit)
    if p.returncode:
        msg=p.stderr.decode(errors='replace').strip()
        if '-1743' in msg:raise ValueError('APPLE_EVENT_DENIED')
        if '-1744' in msg:raise ValueError('APPLE_EVENT_CONSENT_REQUIRED')
        raise ValueError(msg if re.fullmatch(r'[A-Z_0-9]{1,100}',msg) else 'HOST_OBSERVATION_UNAVAILABLE')
    return json.loads(p.stdout)
def sample(base, site, family, nonce, keep=None):
    if family not in ('chrome','edge') or not re.fullmatch(r'[A-Za-z0-9_-]{1,160}',nonce):
        raise ValueError('INVALID_SAMPLE_ARGUMENTS')
    private_scope = base/'active-scope.json'
    scoped = read(private_scope) if private_scope.is_file() else {}
    parked = logical(base,scoped) if scoped else None
    if parked: scoped={}
    state = Path(scoped['root'])/'signed60'/family if scoped.get('family') == family else None
    checks=dict.fromkeys(CHECKS,False)
    original, target, cause = {}, None, None
    exe=Path(__file__).resolve().parent/'window-evidence'
    if state and state.parent.parent.parent.resolve()==base and (state/'original-entry.json').is_file() and not (state/'closed.json').exists():
        try:
            env=command([exe,'original',state,family])
            original=env['original'];page=command([site/'observer',state])
            raw=base64.b64decode(page['payloadBase64'],validate=True);p=json.loads(raw)
            if hashlib.sha256(raw).hexdigest()!=page['sha256'] or p!=page['payload']: raise ValueError('PAGE_RECEIPT_HASH_MISMATCH')
            web=p['page'];flags=web['observationState'];entry=read(state/'original-entry.json')
            if not (p['pid']==original['pid'] and p['sessionID']==original['birth'] and
                p['windowID']==original['nativeWindowID'] and p['tabID']==original['nativeTabID'] and
                web['entryID']==entry['entryID'] and web['timeOrigin']==entry['timeOrigin'] and
                p['family']==family and p['exactTemporaryURL']):raise ValueError('ORIGINAL_ROUTE_CHANGED')
            target=digest([p['sessionID'],p['windowID'],p['tabID'],web['entryID'],web['timeOrigin'],entry['sourceDoc'],read(base/'candidate.json')['dmgSHA256']])
            # Keep the raw WindowServer proof and require an independent hit on
            # the surface. An overlay's rectangular bounds can cover clear pixels.
            hit_proof = original.get('originalAXHits', {})
            surface_hit = hit_proof.get('blockedByProtectedSurface') is False and (
                original['centerHitOriginalCG'] is True or (
                    original.get('originalAXHitQuorum') is True and original['axOriginalWindow'] is True))
            checks=dict(zip(CHECKS,[original['systemForeground'] and p['systemForeground'],original['nativeVisible'],original['cgWindowOnScreen'] and surface_hit,original['axOriginalWindow'],original['selected'] and p['originalSelection'],flags['visible'],flags['focused'],web['signedIn'],web['editor'],web['uploadEntry'],original['singleTab'] and p['originalSoleTab'],original['knownOriginalProcess'] and p['dynamicSignature']]))
        except (KeyError,ValueError,OSError,subprocess.SubprocessError) as e:
            env=command([exe,'environment']);cause=str(e)[:100]
    else:
        env=command([exe,'environment'])
    manager=subprocess.run(['/bin/launchctl','managername'],capture_output=True,text=True,timeout=3).stdout.strip()
    permission=env.get('browsers',{}).get(family,{}).get('aePermission')
    eligible=env['eligibleForPreparation'] and manager=='Aqua' and permission=='ALLOWED'
    stable={k:env[k] for k in ['frontBundle','systemDialogOnScreen','protectedForeground','frontHasModal','displayAwake','screenLocked','onConsole','loginDone','consoleUIDMatches','axTrusted']}
    stable['eligibleForPreparation']=eligible;stable['launchManager']=manager
    stable['browsers']={f:{k:v[k] for k in ['running','hidden','regular','axWindowCount','cgOnScreenCount','aePermission','axWindowAttributeReadable'] if k in v} for f,v in env['browsers'].items()}
    journal(base,family,env,checks,cause,state is not None,manager,target)
    if keep:keep({'nativeReceipt':env,'checks':checks,'cause':cause,'currentCase':scoped.get('case')})
    return {'schema':1,'nonce':nonce,'family':family,'digest':digest(stable),'environment':{'eligibleForPreparation':eligible,'protectedForeground':env['protectedForeground'],'systemDialogOnScreen':env['systemDialogOnScreen'],'displayAwake':env['displayAwake'],'launchManager':manager},'targetKey':target,'checks':checks,'ready':bool(eligible and all(v is True for v in checks.values())),'heldCase':scoped.get('case') if state and not (state/'closed.json').is_file() else None,'scopeReadError':cause}
