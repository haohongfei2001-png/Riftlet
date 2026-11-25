"""Run the signed previous version and operate its real Sparkle UI on a fresh hosted Mac."""
from contextlib import contextmanager, nullcontext
import shutil
from datetime import datetime, timezone
import hashlib
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import runpy
import sqlite3
import subprocess
import time
import xml.etree.ElementTree as ET

testdir = Path(__file__).resolve().parent
repo = testdir.parents[1]
common = runpy.run_path(str(testdir.parent / 'ReleaseUpgradeHost/run.py'))
call, wait, sha = (common[k] for k in ('call', 'wait_for', 'sha'))
assert common['safe_context']() and os.environ['GITHUB_REF'] == 'refs/heads/codex/riftlet-111-public-upgrade-qa'
assert call('stat', '-f%Su', '/dev/console').stdout.strip() == call('id', '-un').stdout.strip()
mode = os.environ['UPGRADE_MODE']
assert mode in ('preflight', 'upgrade', 'private-upgrade')
private = mode == 'private-upgrade'
upgrading = mode != 'preflight'
local = runpy.run_path(str(testdir/'private_feed.py')) if private else None
version, build = ('1.0.11', '67') if upgrading else ('1.0.10', '65')
previous = '036a41733a57810824a830b0090e7360de22cdba3819704484bb01053da7033d'
candidate = os.environ.get('UPGRADE_DMG_SHA256', '') if upgrading else previous
assert re.fullmatch(r'[a-f0-9]{64}', candidate)
assert upgrading == (candidate != previous)
rooturl = 'https://github.com/haohongfei2001-png/Riftlet/releases/download/'
feedurl = 'https://riftlet.com/updates/stable.xml'
app = Path.home() / 'Applications/Riftlet.app'
data = Path.home() / 'Library/Application Support/Riftlet'
witness = Path.home() / 'Library/Containers/com.riftlet.qa.ProductUpgradeUI.xctrunner/Data/RiftletPublicUpgradeWitness'
work = Path(os.environ['RUNNER_TEMP']) / 'public-sparkle'
out = repo / 'test-results/public-sparkle.json'
out.parent.mkdir(exist_ok=True)
proof = {'status':'INCOMPLETE', 'mode':mode, 'workflow':os.environ['GITHUB_RUN_ID'],
         'qaSource':os.environ['GITHUB_SHA'], 'system':call('sw_vers','-productVersion').stdout.decode().strip(),
         'scope':'Publicly downloaded, unmodified Developer ID applications and public signed feed. Synthetic PNGs in a fresh hosted account.'}

if private:
    proof['scope']='Public signed 65, locally signed loopback feed, private draft 67 DMG, disposable hosted Mac and its actual Sparkle UI.'

def open_old():
    extra=['--args','-SUFeedURL',local['base_url']+'private.xml'] if private else []
    call('open','-n','-g',app,*extra)

def get(url, dest):
    call('curl', '--proto', '=https', '--proto-redir', '=https', '--fail', '--location',
         '--silent', '--show-error', '--max-time', '120', '-o', dest, url, timeout=130)

@contextmanager
def volume(dmg, name):
    mount = work / name
    mount.mkdir()
    call('hdiutil','attach',dmg,'-readonly','-nobrowse','-mountpoint',mount)
    try:
        yield mount / 'Riftlet.app'
    finally:
        call('hdiutil','detach',mount)

def inspect(path, ver, num):
    info = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
    assert [info[k] for k in ('CFBundleIdentifier','CFBundleShortVersionString','CFBundleVersion','SUFeedURL')] == ['com.riftlet.app',ver,num,feedurl]
    assert info['SUVerifyUpdateBeforeExtraction'] and info['SURequireSignedFeed']
    call('codesign','--verify','--deep','--strict','--all-architectures',path)
    call('xcrun','stapler','validate',path)
    call('spctl','--assess','--type','execute','--verbose=4',path, timeout=80)
    slices={}
    for arch in ('x86_64','arm64'):
        ds=call('codesign','-dvvv','--arch',arch,path).stderr.decode()
        assert 'TeamIdentifier=ZB9D4T66QB' in ds and 'Authority=Developer ID Application:' in ds
        slices[arch]=re.search(r'^CDHash=([a-f0-9]{40})$',ds,re.M)[1]
    return {'version':ver,'build':num,'codeDirectories':slices,
            'binarySHA256':sha(path/'Contents/MacOS/Riftlet'),'appTicket':'VALID','gatekeeper':'ACCEPTED'}

def save_database(name):
    target=work/name
    with sqlite3.connect((data/'queue.sqlite').as_uri()+'?mode=ro',uri=True) as src, sqlite3.connect(target) as dst:
        src.backup(dst)
        assert dst.execute('PRAGMA quick_check').fetchall()==[('ok',)]
    return sha(target)

def pref(key): return call('defaults','read','com.riftlet.app',key).stdout.decode().strip()

def waiting_pid(different=None):
    def lookup():
        result=call(work/'process','pid',app,check=False)
        if result.returncode==0 and int(result.stdout)!=different:
            return int(result.stdout)
    return wait(lookup,'verified ordinary process at the installed path')

def run():
    assert not any(os.path.lexists(f) for f in (app,data,witness,work))
    assert call('defaults','read','com.riftlet.app',check=False).returncode!=0
    assert call('pgrep','-x','Riftlet',check=False).returncode!=0
    work.mkdir(mode=0o700)
    source=work/'source';source.mkdir()
    fixture=runpy.run_path(str(testdir/'fixture.py'))['build'](repo,work)
    process=work/'process'; verifier=work/'verify'
    call('xcrun','swiftc',testdir.parent/'ReleaseUpgradeHost/app-process.swift','-o',process,timeout=100)
    call('xcrun','swiftc',repo/'scripts/verify-update-signature.swift','-o',verifier,timeout=100)
    baseline=work/'Riftlet-1.0.10.dmg';get(rooturl+'v1.0.10/'+baseline.name,baseline)
    assert sha(baseline)==previous
    call('xcrun','stapler','validate',baseline)
    call('spctl','--assess','--type','open','--context','context:primary-signature',baseline,timeout=80)
    app.parent.mkdir(exist_ok=True)
    with volume(baseline,'old') as released:
        call('ditto','--rsrc','--extattr',released,app)
    proof['startingApp']=inspect(app,'1.0.10','65')
    info=app/'Contents/Info.plist'
    feed=work/'live.xml'
    if private:
        shutil.copyfile(local['private_dir']/'private.xml',feed)
    else:
        get(feedurl,feed)
    call(verifier,info,feed)
    ns='{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    items=ET.parse(feed).findall('./channel/item')
    assert len(items)==1 and items[0].findtext(ns+'version')==build and items[0].findtext(ns+'shortVersionString')==version
    enc=items[0].find('enclosure');archive=work/('Riftlet-'+version+'.dmg')
    if private:
        assert enc.get('url')==local['base_url']+archive.name
        shutil.copyfile(local['private_dir']/archive.name,archive)
    else:
        assert enc.get('url')==rooturl+'v'+version+'/'+archive.name
        if upgrading: get(enc.get('url'),archive)
    assert sha(archive)==candidate and archive.stat().st_size==int(enc.get('length'))
    call(verifier,info,archive,enc.get(ns+'edSignature'))
    proof['privateFeed' if private else 'publicFeed']={'build':build,'sha256':sha(feed),'enclosureSHA256':sha(archive),'oldPublicKeyVerifiedFeedAndEnclosure':True}
    expected=proof['startingApp']
    if upgrading:
        call('xcrun','stapler','validate',archive)
        call('spctl','--assess','--type','open','--context','context:primary-signature',archive,timeout=80)
        with volume(archive,'candidate-reference') as candidate_app:
            expected=inspect(candidate_app,version,build)  # no copying of the new bundle
    call('defaults','write','com.apple.screencapture','location','-string',source)
    # Returning installation in an isolated disposable account, with checks explicitly manual.
    key='Riftlet.firstUse.presented.v1.Riftlet'
    call('defaults','write','com.riftlet.app',key,'-bool','true')
    call('defaults','write','com.riftlet.app','SUEnableAutomaticChecks','-bool','false')
    call('defaults','write','com.riftlet.app','historyDisplayStyle','-string','imageGrid')
    open_old()
    old=waiting_pid()
    wait(lambda:call('lsof','-nP','-a','-p',old,'-Ffn',source,check=False).returncode==0,'old collection folder')
    inputs=[common['collect_fixture'](source,seed,data) for seed in (43,199)]
    first_pid=old
    # Work through the released Core exclusively in a separate fixture directory while the
    # old app is stopped; never edit the ordinary app's database through SQL.
    call(process,'quit',app)
    detached=work/'detached65'
    common['move_idle_root'](data,detached,process,app)
    try:
        # Build 65 documents {} as its user-selected 'off' lifecycle preference.
        # Prevent the normal idle-archive timer from independently changing fixture rows.
        lifecycle=detached/'lifecycle-settings.json'
        assert not lifecycle.is_symlink()
        if lifecycle.exists(): assert isinstance(json.loads(lifecycle.read_text()),dict)
        lifecycle.write_text('{}\n')
        old_sample=json.loads(call(fixture,detached,inputs[0]).stdout)
    finally:
        assert not data.exists()
        detached.rename(data)
    open_old()
    old=waiting_pid(different=first_pid)
    wait(lambda:call('lsof','-nP','-a','-p',old,'-Ffn',source,check=False).returncode==0,'old collector after restoring QA fixture')
    before=common['snapshot'](data)
    assert len(before['assets'])==2 and len(set(inputs))==2 and set(before['media'].values())==set(inputs)
    assert len(before['journals'])==2 and before['upload_starts']==0
    assert before['operations']==1
    def operation_proof():
        oid=old_sample['operationID']; aid=old_sample['assetID']; iid=old_sample['invocationID']
        with sqlite3.connect((data/'queue.sqlite').as_uri()+'?mode=ro',uri=True) as db:
            row=db.execute('SELECT asset_id, attempt, phase, receipt_json FROM operations WHERE id=?',(oid,)).fetchone()
            assert row[:3]==(aid,1,'unknown') and old_sample['attempt']==row[1]
            receipt=json.loads(row[3])
            assert receipt['operationID']==oid and receipt['assetID']==aid and receipt['attempt']==row[1]
            assert receipt['assetSHA256']==inputs[0] and receipt['outcome']=='unknown' and receipt['profileID']=='offline-upgrade-qa'
            assert receipt['safeToRetry'] is False
            cp=db.execute('SELECT value FROM checkpoints WHERE key=?',('transfer-dispatch-call-v1:'+oid,)).fetchone()[0]
            raw=base64.b64decode(cp); invocation=json.loads(raw)
            assert invocation['invocationID']==iid and invocation['operationID']==oid
            assert invocation['returnedReceipt']==receipt and invocation['inputExecutionReturned'] is True
            visible=db.execute('SELECT visibility,visibility_reason,status FROM assets WHERE id=?',(aid,)).fetchone()
            assert visible[:2]==('swallowed','traySelection') and visible[2]=='unknown'
            return {'assetID':aid,'assetPNG':inputs[0],'operationID':oid,'attempt':row[1],'phase':row[2],
                    'invocationID':iid,'historyVisibility':visible[0],'historyReason':visible[1],
                    'receiptSHA256':hashlib.sha256(row[3].encode()).hexdigest(),'dispatchCheckpointSHA256':hashlib.sha256(raw).hexdigest(),
                    'fixtureScope':'Synthetic offline UNKNOWN created with signed build 65 source QueueStore APIs in an idle, detached, hosted test library; real build 65 collected the PNGs.'}
    old_op=operation_proof()
    prefs={k:pref(k) for k in (key,'SUEnableAutomaticChecks','historyDisplayStyle')}
    assert prefs['historyDisplayStyle']=='imageGrid'
    proof['oldLibrary']={'sqliteSnapshotSHA256':save_database('before.sqlite'),'assetCount':2,'originalPNGHashes':inputs,'preferences':prefs,
                         'schema':before['schema'],'assetIDs':[a['id'] for a in before['assets']],'oldPID':old,'syntheticHistoricOperation':old_op}
    args=['xcodebuild','-project',str(testdir/'ProductUpgrade.xcodeproj'),'-scheme','PublicUpgrade',
          '-destination','platform=macOS,arch=x86_64','-derivedDataPath',str(work/'derived'),
          '-parallel-testing-enabled','NO','-only-testing:ProductUpgradeUI/PublicUpgradeUI/'+('testCurrentVersion' if mode=='preflight' else 'testPublicUpgrade'),'-resultBundlePath',str(work/'UI.xcresult'),'test']
    attempt=subprocess.run(args,timeout=480)
    proof['userSteps']={p.name:p.read_text() for p in sorted(witness.iterdir())} if witness.exists() else {}
    if attempt.returncode: raise RuntimeError('XCTest exit '+str(attempt.returncode))
    steps={'user-check','up-to-date'} if mode=='preflight' else {'user-check','user-install','user-relaunch'}
    assert set(proof['userSteps'])==steps
    if upgrading:
        new=waiting_pid(different=old)
        assert call('ps','-p',old,'-o','comm=',check=False).returncode!=0
    else:
        new=waiting_pid()
        assert new==old
    assert inspect(app,version,build)==expected
    after=common['snapshot'](data)
    for part in ('assets','operationRows','startRows','media','journals'): assert before[part]==after[part],part
    assert all(pref(k)==v for k,v in prefs.items())
    assert operation_proof()==old_op and old_op is not None
    assert json.loads((data/'lifecycle-settings.json').read_text())=={}
    assert [sha(source/name) for name in ('Screenshot-identity-43.png','Screenshot-identity-199.png')]==inputs
    proof['retainedLibrary']={'sqliteSnapshotSHA256':save_database('after.sqlite'),'oldRowsAndMediaExact':True,'preferencesUnchanged':True,
                              'newPID':new,'installed':expected,'retainedHistoricOperation':old_op}
    proof['status']='PRIVATE_LOOPBACK_IN_APP_UPGRADE_PASS' if private else ('PUBLIC_IN_APP_UPGRADE_PASS' if upgrading else 'PUBLIC_BUILD_65_UP_TO_DATE_PREFLIGHT_PASS')

try:
    with (local['serve']() if private else nullcontext()) as requests:
        run()
    if private:
        assert 'private.xml' in requests and local['archive_name'] in requests
        proof['loopback']={'source':'Signed process launch argument for build 65','requests':requests,'serverStopped':True,
                           'onlyLocal':True,'persistentFeedOverride':call('defaults','read','com.riftlet.app','SUFeedURL',check=False).returncode==0}
        assert proof['loopback']['persistentFeedOverride'] is False
except Exception:
    proof['status']='INCOMPLETE'
    raise
finally:
    if witness.exists():
        proof['userSteps']={f.name:f.read_text() for f in witness.iterdir() if f.name!='mode'}
    if (work/'process').is_file() and app.exists():
        call(work/'process','quit',app,check=False)
    proof['utc']=datetime.now(timezone.utc).isoformat()
    out.write_text(json.dumps(proof,indent=2)+'\n')
