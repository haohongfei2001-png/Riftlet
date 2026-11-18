#!/usr/bin/env python3
"""Compare real WindowServer PNGs recorded by --desktop-forms-review (macOS)."""
import argparse
import hashlib
import json
import math
import struct
import subprocess
import tempfile
from pathlib import Path

COLORS = ('default', 'violet', 'blue', 'teal', 'coral', 'graphite', 'black', 'white', 'saturated')


def pixels(directory, frame, temporary):
    source = directory / (frame['name'] + '.png')
    if hashlib.sha256(source.read_bytes()).hexdigest() != frame['sha256']:
        raise ValueError(f'PNG digest mismatch for {source.name}')
    target = temporary / (source.stem + '.bmp')
    subprocess.run(['/usr/bin/sips', '-s', 'format', 'bmp', str(source), '--out', str(target)],
                   check=True, stdout=subprocess.DEVNULL)
    data = target.read_bytes()
    offset, = struct.unpack_from('<I', data, 10)
    w, h, planes, depth, compression = struct.unpack_from('<iiHHI', data, 18)
    if (data[:2] != b'BM' or planes != 1 or depth != 32 or compression != 3 or
            [w, abs(h)] != frame['pixels'] or len(data) - offset != 4 * w * abs(h)):
        raise ValueError('Unable to decode lossless macOS BGRA bitmap')
    bgra = data[offset:]
    if h > 0:
        stride = w * 4
        bgra = b''.join(bgra[i:i + stride] for i in range((h - 1) * stride, -1, -stride))
    return bgra


def regions(frame, mask):
    w, h = frame['pixels']
    qx, qy, qw, qh = frame['quartzBounds']
    kx, ky, kw, kh = mask['key']
    scale = min(mask['tray'][2] / 246, kw / 36, kh / 32)
    foot = min(4.5 * mask['tray'][2] / 246, kh * .08)
    cx, cy = kx + kw / 2, ky + (kh + foot) / 2
    lens_y = cy - 1.8 * scale

    def contains(rect, x, y):
        left, bottom, width, height = rect
        return left <= x < left + width and bottom <= y < bottom + height

    result = {k: [] for k in ('body', 'lens', 'key', 'thumbnails', 'material')}
    for py in range(h):
        y = mask['primaryTop'] - (qy + (py + .5) * qh / h)
        for px in range(w):
            x = qx + (px + .5) * qw / w
            if math.hypot(x - cx, y - lens_y) <= 2.5 * scale:
                region = 'lens'
            elif abs(x - cx) <= 15 * scale + qw / w and abs(y - cy) <= 13 * scale + qh / h:
                region = 'body'  # canonical 28 × 24 silhouette plus one antialias pixel
            elif contains(mask['key'], x, y):
                region = 'key'
            elif any(contains(r, x, y) for r in frame['inputFrames']):
                region = 'thumbnails'
            else:
                region = 'material'
            result[region].append((py * w + px) * 4)
    return result


def different(a, b, offsets):
    return sum(a[i:i + 4] != b[i:i + 4] for i in offsets)


def evaluate(report, directory, temporary):
    masks = {m['name']: m for m in report['artifacts'] if m['kind'] == 'trayAppearanceMask'}
    frames = {f['name']: f for f in report['frames'] if f['name'] in masks}
    results = []
    for style in ('light', 'dark'):
        prefix = f'appearance-{style}-'
        base = frames[prefix + 'default']
        mask = masks[base['name']]
        region = regions(base, mask)
        if not all(region.values()):
            raise ValueError('Empty comparison region')
        values = {}
        for variant in (*COLORS, 'opaque', 't01', 't75'):
            name = prefix + variant
            frame = frames[name]
            if (any(frame[k] != base[k] for k in ('pixels', 'quartzBounds', 'inputFrames', 'rowIDs')) or
                    any(masks[name][k] != mask[k] for k in ('key', 'tray', 'primaryTop'))):
                raise ValueError(f'Geometry or screenshot identity moved during {name}')
            values[variant] = pixels(directory, frame, temporary)
        # Use the saturated custom color as the counterfactual for the default and black/white,
        # which can legitimately coincide under system tint. Every tested color gets a distinct pair.
        for variant in COLORS:
            baseline = 'saturated' if variant != 'saturated' else 'blue'
            counts = {label: different(values[variant], values[baseline], indices) for label, indices in region.items()}
            ok = counts['body'] > len(region['body']) * .10 and all(n == 0 for k, n in counts.items() if k != 'body')
            results.append(dict(appearance=style, variant=variant, baseline=baseline, changedPixels=counts, passed=ok))
        for variant in ('default', 't01', 't75'):
            counts = {k: different(values[variant], values['opaque'], region[k]) for k in ('lens', 'material')}
            # A physical translucent wash changes its surroundings, including compositing behind
            # translucent tiles. The neutral opaque lens itself must never change.
            results.append(dict(appearance=style, variant=variant, baseline='opaque', changedPixels=counts,
                                passed=counts['lens'] == 0 and counts['material'] > 0))
    return results


def verify_desktop_run(report, folder):
    forms = ('tray', 'windChime', 'microSlit')
    expected = {f'{form}-{count}' for form in forms for count in (0, 1, 2, 3, 4, 5, 10)}
    expected.update(f'collect-fixture-{count}' for count in range(1, 11))
    expected.update(f'{mode}-{edge}Middle' for mode in ('light', 'dark') for edge in ('left', 'right'))
    expected.update(('isolated-review-controls', 'tray-native-wheel', 'tray-owned-button-and-escape',
                     'actual-tray-appearance-layers', 'violet-restart-and-material-switch',
                     'physical-connected-displays', 'native-high-contrast-appearance-override',
                     'tray-restart-baseline'))
    cases = report.get('cases', [])
    names = [case.get('case') for case in cases]
    if (report.get('reviewMode') != 'desktopForms' or not report.get('completed')
            or report.get('status') != 'PASS_SCOPED_NATIVE_REVIEW' or not expected.issubset(names)
            or len(set(names)) != len(names) or any(case.get('status') != 'PASS' for case in cases)):
        raise ValueError("Desktop review did not pass every required case")
    for frame in report['frames']:
        if frame['status'] != 'RECORDED_NATIVE_WINDOWSERVER':
            raise ValueError("Incomplete desktop frame: " + frame['name'])
        name = frame.get('file', frame['name'] + '.png')
        path = folder / name
        if Path(name).name != name or path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != frame['sha256']:
            raise ValueError("Desktop frame identity mismatch: " + frame['name'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    report = json.loads(args.report.read_bytes())
    verify_desktop_run(report, args.report.parent)
    with tempfile.TemporaryDirectory() as tmp:
        results = evaluate(report, args.report.parent, Path(tmp))
    good = all(entry['passed'] for entry in results)
    print(json.dumps({'status': 'PASS' if good else 'FAIL', 'source': report['executableSHA256'],
                      'samples': results}, indent=2))
    raise SystemExit(0 if good else 1)
