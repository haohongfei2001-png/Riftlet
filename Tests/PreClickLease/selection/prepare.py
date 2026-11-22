"""Prepare one fixed QA sentence and selected phrase on the already admitted original editor.
This module has no code path to open, focus, or find a browser window.
"""
import json
import os
from pathlib import Path
import select
import subprocess

FAMILIES = {'com.google.Chrome':'chrome','com.microsoft.edgemac':'edge'}
KEYS = ('documentID','composerID','draftEpoch')

def check(ok, reason):
    if not ok:
        raise ValueError(reason)

def prepare(route, native_scope, dom_state, output_dir, executable):
    """native_scope() reads current guarded native route; dom_state() is the original witness.state.
    Requires an identifiable original editor in the active, authenticated Temporary Chat with a seed.
    output_dir must exist and be unique for the attempt. Any issued edit remains one-shot.
    """
    bundle = route['applicationID']
    family = FAMILIES[bundle]
    parts = route['session'].split(':')
    check(len(parts)==4 and parts[0]==family+'-kernel-v1' and all(x.isdecimal() for x in parts[1:]),'INVALID_SESSION')
    pid = int(parts[1])
    def guard(text_state, previous=None, focused=True):
        native=native_scope()
        check(native.get('bundle')==bundle and native.get('pid')==pid and native.get('sessionID')==route['session']
              and all(native.get(k)==route[k] for k in ('windowID','tabID'))
              and all(native.get(k) is True for k in ('dynamicSignature','exactTemporaryURL','originalSelection','originalSoleTab','systemForeground')), 'NATIVE_SCOPE_CHANGED')
        state=dom_state()
        check(state.get('original') is True and (not focused or state.get('activeOriginal') is True) and
              state.get('textState')==text_state and state.get('oldCardsIntact') is True and
              isinstance(state.get('priorCardCount'),int) and state['priorCardCount']>0 and
              all(state.get(k)==0 for k in ('sendClicks','formSubmits')),'ORIGINAL_DOM_SCOPE_CHANGED')
        check(all(isinstance(state.get(k),str) and state[k] for k in KEYS),'MISSING_DRAFT_IDS')
        if previous is not None:
            check(all(state[k]==previous[k] for k in (*KEYS,'priorCardCount')),'ORIGINAL_DRAFT_CHANGED')
        return state
    initial=guard('empty',focused=False)
    out=Path(output_dir)
    marker=out/'selection-preparation-once.json'
    steps=[]
    def persist(label):
        steps.append(label)
        data=json.dumps({'nativeRoute':route,'originalDraft':{k:initial[k] for k in KEYS},'steps':steps},sort_keys=True).encode()+b'\n'
        # Keep the original exclusive claim throughout; the append-only log is readable after partial failure.
        with marker.open('ab') as f:
            f.write(data);f.flush();os.fsync(f.fileno())
    with marker.open('xb') as f:
        os.fchmod(f.fileno(),0o600)
    p=subprocess.Popen([str(executable),family,str(pid),route['session'],json.dumps(initial['geometry'],separators=(',',':'))],text=True,
                       stdout=subprocess.PIPE,stderr=subprocess.PIPE,stdin=subprocess.PIPE)
    def expect(*allowed):
        check(bool(select.select([p.stdout],[],[],15)[0]),'AX_READ_TIMEOUT')
        result=p.stdout.readline().strip()
        if result not in allowed:
            raise RuntimeError(p.stderr.read(220) if p.poll() is not None or not result else 'UNEXPECTED_AX_REPLY')
        return result
    def reply(token,proof):
        p.stdin.write(json.dumps({'token':token,'geometry':proof['geometry']},separators=(',',':'))+'\n');p.stdin.flush()
    try:
        first=expect('READY_EMPTY','CAN_FOCUS_ORIGINAL')
        if first=='CAN_FOCUS_ORIGINAL':
            original=guard('empty',initial,focused=False)
            persist('EXACT_MAPPED_FOCUS_INTENT');reply('FOCUS_ONCE',original)
            expect('READY_EMPTY')
        original=guard('empty',initial);persist('INSERT_INTENT');reply('INSERT_ONCE',original)
        expect('TEXT_PRESENT')
        original=guard('expected',initial);persist('SELECT_INTENT');reply('SELECT_ONCE',original)
        expect('SELECTION_PRESENT')
        check(p.wait(timeout=2)==0,'AX_EXIT_FAILURE')
        guard('expected',initial);persist('AX_RANGE_CONFIRMED')
        return {'selectedRangeUTF16':[12,40],'axChecksPassed':True,'domIdRequired':False,'mappedFocusIssued':first=='CAN_FOCUS_ORIGINAL','crossCheckedHitPoints':2,'original':{k:initial[k] for k in KEYS}}
    finally:
        try:
            p.stdin.close()
        except BrokenPipeError:
            pass
        if p.poll() is None:
            p.kill()
        p.wait(timeout=2)
        p.stdout.close()
        p.stderr.close()
