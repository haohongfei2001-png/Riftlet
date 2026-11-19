"""Compare editorial motion from decoded video; never infer viewer quality from a score.

Requires PyAV and NumPy. --shots accepts comma separated shot starts (seconds).
"""
import argparse
from collections import deque
from hashlib import sha256
import json
from pathlib import Path

import av
import numpy as np


def fraction(mask):
    return round(float(np.mean(mask)), 5) if len(mask) else None


def runs(flags, pairs):
    found = []
    index = 0
    while index < len(flags):
        if not flags[index]:
            index += 1
            continue
        first = index
        while index < len(flags) and flags[index]:
            index += 1
        start, end = pairs[first]['from'], pairs[index-1]['to']
        found.append([round(start,3),round(end,3),round(end-start,3)])
    return sorted(found,key=lambda r:-r[-1])


def compare(left, right):
    diff = np.abs(left-right)
    return float(np.mean(diff)), float(np.mean(diff >= 4)), float(np.mean(diff >= 20))


def analyze(path, shots):
    rows, pts = [], []
    with av.open(str(path)) as source:
        video = source.streams.video[0]
        fps = float(video.average_rate)
        target_delta = .25
        history = deque(maxlen=max(2,int(np.ceil(fps*target_delta))+1))
        old_exact = None
        for frame in source.decode(video):
            second = float(frame.pts * frame.time_base)
            full = frame.to_ndarray(format='gray')
            exact = sha256(full).digest()
            sample = frame.reformat(width=320,height=180,format='gray',interpolation='AREA').to_ndarray().astype(np.int16)
            if history:
                mad,active,big = compare(history[-1],sample)
                # Inspect central 76% (both horizontal edges retained). This
                # excludes title-band typography, footer captions and their cuts.
                lag_motion = None
                lag_pts = None
                if history and second-pts[max(0,len(pts)-len(history))] >= target_delta-1e-10:
                    index = min(range(len(history)),key=lambda i: abs(pts[len(pts)-len(history)+i]-(second-target_delta)))
                    lag_motion = compare(history[index][22:158],sample[22:158])[1]
                    lag_pts = pts[len(pts)-len(history)+index]
                rows.append({'from':pts[-1],'to':second,'exact_luma':exact==old_exact,
                             'mad':mad,'area4':active,'jump':big>=.32 and mad>=12,
                             'quarter_core_area4':lag_motion,'quarter_pts':lag_pts})
            history.append(sample)
            pts.append(second)
            old_exact = exact
    flags = [r['area4'] < .0015 for r in rows]
    def summary(rs):
        qs = [r['quarter_core_area4'] for r in rs if r['quarter_core_area4'] is not None]
        return {'pairs':len(rs), 'full_luma_exact_ratio':fraction([r['exact_luma'] for r in rs]),
                'near_still_ratio':fraction([r['area4']<.0015 for r in rs]),
                'moving_central_area_median_over_quarter_second':round(float(np.median(qs)),5) if qs else None,
                'broad_motion_over_quarter_second_ratio':fraction([n >= .02 for n in qs]),
                'quiet_core_over_quarter_second_ratio':fraction([n < .0015 for n in qs])}
    duration = pts[-1] + 1/fps
    intervals=sorted(set([0]+[i for i in shots if 0<=i<duration])) + [duration]
    shots_report={}
    for a,b in zip(intervals,intervals[1:]):
        # Exclude lag crossing shot boundaries. Adjacent observations are retained
        # for whole-film freeze runs, which reflect viewers' total waiting time.
        rs = [r for r in rows if a <= r['to'] < b and r['quarter_pts'] is not None and r['quarter_pts'] >= a]
        shots_report[f'{a:g}-{b:g}'] = summary(rs)
    dt=np.diff(np.array(pts))
    return {'file':path.name,'sha256':sha256(path.read_bytes()).hexdigest(),'frames':len(pts),
            'duration':round(duration,3),'fps':fps,'pts_min_step':round(float(min(dt)),6),
            'pts_max_step':round(float(max(dt)),6),'nonmonotonic_pts_count':int(np.sum(dt<=0)),
            'summary':summary(rows),'near_still_runs_s':[r for r in runs(flags, rows) if r[-1]>=.55],
            'persistent_quiet_core_windows_s':[r for r in runs([p['quarter_core_area4'] is not None and p['quarter_core_area4']<.0015 for p in rows], rows) if r[-1]>=.55],
            'broad_discontinuities_s':[round(r['to'],3) for r in rows if r['jump']],
            'shots':shots_report}


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('movie',type=Path)
    ap.add_argument('--shots',default='0')
    ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args()
    result=analyze(args.movie,[float(t) for t in args.shots.split(',')])
    args.out.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))
