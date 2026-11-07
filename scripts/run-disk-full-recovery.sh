#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "--help" || $# -ne 1 ]]; then
  cat <<'USAGE'
Usage: run-disk-full-recovery.sh NEW_OUTPUT_DIR
Build a native synthetic-only probe, create one new 128 MiB sparse HFS+ image,
verify its UUID/image/device/mount identity, exercise real full-volume failures,
then normally detach only that image. No App, GUI, production data or network.
All original files, the image and evidence remain. Only owned disposable fillers
are removed by the native probe after their inode and device are checked.
USAGE
  [[ "${1:-}" == "--help" ]] && exit 0
  exit 64
fi
exec python3 - "$0" "$1" <<'PY'
from pathlib import Path
import datetime, hashlib, json, os, plistlib, re, shutil, sqlite3, stat, subprocess, sys, time, uuid

repo = Path(sys.argv[1]).resolve().parent.parent
out = Path(sys.argv[2])
assert out.is_absolute() and out.parent.is_dir() and out.parent.resolve() == out.parent
assert not out.exists() and not out.is_symlink(), 'Never overwrite evidence'
out.mkdir(mode=0o700)
os.chdir(repo)
identifier = str(uuid.uuid4())
image = out / ('test-' + identifier + '.sparseimage')
mount = out / 'mount'
mount.mkdir()
evidence = out / 'evidence'
evidence.mkdir()
root = mount / ('riftlet-diskfull-' + identifier)
binary = out / 'disk-full-recovery'
maximum = 256 * 1024 * 1024
result = {'schema': 1, 'result': 'FAIL', 'completed': False,
          'startedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'uuid': identifier, 'requestedImageBytes': 128 * 1024 * 1024,
          'maximumPermittedVolumeBytes': maximum,
          'productionDataAccess': False, 'guiOrAppLaunch': False, 'network': False,
          'volumeDetached': False, 'timedOut': False}
attached = False

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(1024 * 1024): h.update(block)
    return h.hexdigest()

def save(name, obj):
    with (out / name).open('x') as stream: json.dump(obj, stream, indent=2); stream.write('\n')

def source_files():
    files = [Path('Package.swift'), Path('Tests/Readiness/NativeDiskFullRecovery.swift'),
             Path('scripts/run-disk-full-recovery.sh')]
    files += [p for area in ['RiftletCore', 'RiftletCapture', 'CSQLite']
              for p in Path('Sources', area).rglob('*') if p.is_file()]
    assert all(not p.is_symlink() for p in files)
    return {p.as_posix(): sha(p) for p in sorted(files)}

def command(args, name, timeout=60, check=True):
    completed = subprocess.run(args, capture_output=True, timeout=timeout)
    (out / (name + '.stdout')).write_bytes(completed.stdout)
    (out / (name + '.stderr')).write_bytes(completed.stderr)
    if check: assert completed.returncode == 0, name + ' failed: ' + str(completed.returncode)
    return completed

def own_image_info(name):
    data = command(['hdiutil', 'info', '-plist'], name).stdout
    info = plistlib.loads(data)
    matching = [entry for entry in info.get('images', [])
                if Path(entry.get('image-path', '/nonexistent')).resolve() == image]
    assert len(matching) <= 1, 'Ambiguous own image identity'
    return matching[0] if matching else None

def inventory(directory):
    files = {}
    for path in sorted(directory.rglob('*')):
        mode = path.lstat().st_mode
        assert not stat.S_ISLNK(mode), 'Unexpected symlink in owned tree'
        if stat.S_ISREG(mode):
            files[path.relative_to(directory).as_posix()] = {
                'sha256': sha(path), 'bytes': path.stat().st_size,
                'mode': format(stat.S_IMODE(mode), '04o')}
    return files

try:
    before = source_files()
    save('source-inputs-before.json', before)
    build = command(['swift', 'build', '--build-system', 'native', '-c', 'release', '-Xswiftc', '-enable-testing',
                     '--scratch-path', str(out / 'build'), '--target', 'RiftletCapture'], 'build', timeout=180)
    bin_path = Path(command(['swift', 'build', '--build-system', 'native', '-c', 'release', '--scratch-path',
                             str(out / 'build'), '--show-bin-path'], 'bin-path').stdout.decode().strip())
    objects = sorted((bin_path / 'RiftletCore.build').glob('*.o')) + sorted((bin_path / 'RiftletCapture.build').glob('*.o'))
    assert objects, 'No native module objects'
    command(['xcrun', 'swiftc', '-O', '-parse-as-library', '-I', str(bin_path / 'Modules'), '-I', 'Sources/CSQLite',
             'Tests/Readiness/NativeDiskFullRecovery.swift', *map(str, objects), '-lsqlite3', '-o', str(binary)],
            'harness-build', timeout=120)
    assert source_files() == before, 'Inputs changed during build; do not execute an ambiguously bound probe'
    save('build-identity.json', {'schema': 1, 'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                               'sourceFiles': before, 'sourceInputsVerifiedBeforeAndAfterBuild': True,
                               'binarySHA256': sha(binary),
                               'moduleObjects': {str(p.relative_to(bin_path)): sha(p) for p in objects},
                               'swiftVersion': subprocess.check_output(['xcrun', 'swiftc', '--version'], text=True).strip(),
                               'scope': 'Exact source hashes bind uncommitted harness bytes; checkout SHA is not a claim the harness was already committed.'})
    result['binarySHA256'] = sha(binary)
    command(['hdiutil', 'create', '-size', '128m', '-type', 'SPARSE', '-fs', 'HFS+', '-nospotlight',
             '-volname', 'RiftletDiskFull-' + identifier[:12], str(image)], 'image-create')
    assert image.is_file() and not image.is_symlink()
    attached_result = command(['hdiutil', 'attach', str(image), '-nobrowse', '-noautoopen',
                               '-mountpoint', str(mount), '-plist'], 'image-attach')
    attached = True
    attach = plistlib.loads(attached_result.stdout)
    candidates = [entry for entry in attach['system-entities'] if entry.get('mount-point') == str(mount)]
    assert len(candidates) == 1, 'Expected exactly one own mounted filesystem'
    mounted_device = candidates[0]['dev-entry']
    assert re.fullmatch(r'/dev/disk\d+(s\d+)?', mounted_device)
    info = plistlib.loads(command(['diskutil', 'info', '-plist', mounted_device], 'volume-info').stdout)
    assert info.get('MountPoint') == str(mount) and info.get('DeviceNode') == mounted_device, 'diskutil device/mount mismatch'
    assert 0 < info['TotalSize'] <= maximum
    assert info.get('FilesystemType') == 'hfs', 'This probe explicitly uses a bounded HFS+ test volume'
    whole_device = '/dev/' + info['ParentWholeDisk'] if 'ParentWholeDisk' in info else mounted_device
    assert re.fullmatch(r'/dev/disk\d+', whole_device)
    assert whole_device in [e.get('dev-entry') for e in attach['system-entities']]
    own = own_image_info('attached-identity')
    assert own and any(e.get('mount-point') == str(mount) and e.get('dev-entry') == mounted_device
                       for e in own['system-entities'])
    assert whole_device in [e.get('dev-entry') for e in own['system-entities']]
    assert os.path.ismount(mount) and mount.stat().st_dev != out.stat().st_dev
    volume_stat = os.statvfs(mount)
    assert 0 < volume_stat.f_blocks * volume_stat.f_frsize <= maximum
    identity = {'kind': 'synthetic-disk-full-recovery', 'uuid': identifier,
                'deviceNumber': mount.stat().st_dev, 'mountedDevice': mounted_device, 'wholeDevice': whole_device,
                'volumeUUID': info.get('VolumeUUID'), 'volumeBytes': info['TotalSize'],
                'image': str(image), 'mountPoint': str(mount), 'filesystem': info['FilesystemType']}
    save('volume-identity.json', identity)
    root.mkdir(mode=0o700)
    (root / 'root-marker.json').write_text(json.dumps(identity, indent=2) + '\n')
    started = time.monotonic()
    with (out / 'runtime.log').open('x') as log:
        process = subprocess.Popen([str(binary), str(root), str(evidence), identifier], stdout=log, stderr=subprocess.STDOUT)
        result['nativePID'] = process.pid
        try: code = process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            result['timedOut'] = True
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
            code = 124
    result.update(nativeExitCode=code, nativeActualSeconds=time.monotonic() - started)
    original_inventory = inventory(root)
    save('volume-files-before-detach.json', {'files': original_inventory})
    # Preserve readable data outside the image too; a failed disposable filler remains in the image.
    shutil.copytree(root, out / 'retained-data', ignore=shutil.ignore_patterns('disposable-filler-*.bin'))
    copied_inventory = inventory(out / 'retained-data')
    expected_copy = {name: value for name, value in original_inventory.items() if not name.startswith('disposable-filler-')}
    assert copied_inventory == expected_copy, 'Retained original/media/journal copy differs'
    save('retained-files.json', {'files': copied_inventory})
    assert code == 0 and not result['timedOut'], 'Native failure remains a failure'
    report = json.loads((evidence / 'native-report.json').read_text())
    result['nativeReportSHA256'] = sha(evidence / 'native-report.json')
    assert report['completed'] and report['result'] == 'PASS_SCOPED_REAL_DISK_FULL_RECOVERY'
    assert all(c['result'] == 'PASS' for c in report['cases']) and all(f['removed'] for f in report['fillers'])
    # SQLite may update its SHM even for a read-only connection; inspect another copy.
    verification = out / 'sqlite-verification'
    verification.mkdir()
    for suffix in ['', '-wal', '-shm']:
        source = out / 'retained-data/private' / ('queue.sqlite' + suffix)
        if source.exists(): shutil.copy2(source, verification / source.name)
    connection = sqlite3.connect((verification / 'queue.sqlite').as_uri() + '?mode=ro', uri=True)
    try:
        assert connection.execute('PRAGMA quick_check').fetchall() == [('ok',)]
        assert connection.execute('PRAGMA foreign_key_check').fetchall() == []
        tables = {row[0]: connection.execute('SELECT count(*) FROM "' + row[0].replace('"', '""') + '"').fetchone()[0]
                  for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")}
        assert tables['assets'] == 4 and tables['operations'] == 1 and tables['upload_starts'] == 0
        assert connection.execute("SELECT count(*) FROM operations WHERE phase='unknown'").fetchone()[0] == 1
        result['database'] = {'quickCheck': 'ok', 'foreignKeyViolations': 0, 'tables': tables, 'unknownOperations': 1}
    finally: connection.close()
    result['nativeValidationPassed'] = True
except Exception as error:
    result['failure'] = repr(error)
finally:
    # Never force-detach, never identify a device only by an unverified numeric suffix.
    try:
        own = own_image_info('cleanup-identity') if image.exists() else None
        if own:
            entities = own.get('system-entities', [])
            whole = [e['dev-entry'] for e in entities if re.fullmatch(r'/dev/disk\d+', e.get('dev-entry', ''))]
            assert len(whole) == 1, 'Cannot unambiguously identify own whole image device'
            mounted = [e.get('mount-point') for e in entities if 'mount-point' in e]
            assert all(point == str(mount) for point in mounted), 'Own image is mounted at an unexpected location'
            detached = command(['hdiutil', 'detach', whole[0]], 'image-detach', timeout=30, check=False)
            result['detachExitCode'] = detached.returncode
            assert detached.returncode == 0, 'OWNED_MOUNT_REMAINS: normal detach failed'
        if image.exists(): assert own_image_info('after-detach-identity') is None
        assert not os.path.ismount(mount), 'OWNED_MOUNT_REMAINS'
        result['volumeDetached'] = True
        if image.exists():
            result['preservedImage'] = {'basename': image.name, 'sha256': sha(image), 'bytes': image.stat().st_size}
    except Exception as error:
        result['cleanupFailure'] = repr(error)
        result['result'] = 'OWNED_MOUNT_REMAINS_OR_IDENTITY_UNCONFIRMED'
    result['completed'] = bool(result.get('nativeValidationPassed') and result['volumeDetached']
                               and not result.get('failure') and not result.get('cleanupFailure'))
    if result['completed']: result['result'] = 'PASS_SCOPED_REAL_DISK_FULL_RECOVERY'
    result['finishedUTC'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save('runner-result.json', result)
    print(json.dumps(result, indent=2))
sys.exit(0 if result['completed'] else 1)
PY
