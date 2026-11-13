#!/usr/bin/env python3
"""15s vertical score. Run alongside score.py (Python 3 + NumPy)."""
import argparse
from pathlib import Path
import numpy as np
from score import Session, SR, opening, master, write_wav


def transcribe_opening(s):
    # Keep the exact master take, including note decays and panning. The second
    # measure is lifted, leaving a short transition into the vertical capture.
    source = Session(30)
    opening(source)
    length = round(2.18 * SR)
    fade = np.ones(length)
    release = round(.16 * SR)
    fade[-release:] = np.linspace(1., 0., release) ** 2
    for name in s.tracks:
        s.tracks[name][:length] += source.tracks[name][:length] * fade[:, None]


def collect(s):
    s.bass(2.24, 38, .40, .60)
    s.drum(2.25, 'heel', .25, -.10)
    s.key(2.24, 69, .22, .45, -.22, .38)
    s.shutter(2.53, .72)
    s.arrival(3.03, .46, 57)
    s.key(3.17, 65, .20, .62, -.20)
    s.bass(3.33, 41, .43, .69)
    s.drum(3.33, 'heel', .24, -.10)
    s.drum(3.59, 'sand', .10, .44)
    s.key(3.88, 69, .205, .46, .15)
    s.drum(3.89, 'rim', .20, .17)
    s.bow(3.48, [57, 64], .89, .054)
    s.shutter(4.43, .69)
    s.arrival(4.83, .47, 59)
    s.bass(4.95, 43, .43, .65)
    s.key(4.985, 67, .225, .60, -.22)
    s.key(5.52, 69, .16, .46, .20)
    s.drum(5.51, 'rim', .20, .16)
    s.drum(5.80, 'sand', .10, .45)
    s.bow(5.18, [59, 64, 67], 1.63, .06)
    s.bass(6.06, 45, .44, .55)
    s.drum(6.06, 'heel', .25, -.10)
    s.key(6.07, 71, .23, .56, -.16)
    s.drum(6.33, 'sand', .09, .44)
    s.key(6.59, 64, .19, .43, .14)
    s.drum(6.61, 'rim', .15, .16)
    s.button(7.54, .79, .24, mouse=True)
    s.attached(7.75)


def keep_working(s):
    s.bass(7.76, 38, .49, .91)
    s.bow(7.93, [57, 64, 65], 1.53, .064)
    for start, root, a, b, c in [(8.30, 38, 62, 64, 69), (10.34, 43, 62, 67, 71)]:
        s.bass(start, root, .45, .63)
        s.drum(start, 'heel', .29, -.08)
        s.key(start + .02, a, .219, .60, -.26)
        s.key(start + .275, b, .147, .59, .06)
        s.drum(start + .530, 'rim', .205, .18)
        s.key(start + .78, c, .266, .59, .23)
        s.drum(start + .80, 'sand', .084, .45)
        s.drum(start + 1.04, 'heel', .182, -.08)
        s.key(start + 1.19, b, .135, .56, -.06)
        s.bass(start + 1.24, root + 7, .235, .34)
    s.bow(9.81, [55, 62, 71], 1.63, .059)
    for at, gain in [(9.60, .19), (9.76, .16), (9.882, .18), (10.05, .15), (10.34, .20), (10.51, .17), (10.664, .19), (10.91, .16), (11.05, .155), (11.19, .215)]:
        s.button(at, gain, s.rng.uniform(-.17, .04))


def signature(s):
    s.bass(12., 38, .44, .79)
    s.key(12.01, 57, .15, .94, -.36)
    s.key(12.033, 65, .15, .93, .14)
    s.key(12.075, 71, .105, .89, .30)
    s.bow(12.026, [57, 65, 71], .89, .064)
    for at, note, gain, ring, pan in [(12.60,62,.33,.76,-.16), (12.95,64,.24,.69,-.06), (13.50,69,.336,1.27,.14)]:
        s.key(at, note, gain, ring, pan, .16)
    s.bass(13.50, 38, .372, .91)
    s.bow(13.48, [50, 59, 65], 1.36, .06)
    s.key(13.53, 74, .100, 1.20, .36, .12)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    opts = parser.parse_args()
    s = Session(15.)
    transcribe_opening(s)
    collect(s)
    keep_working(s)
    signature(s)
    mix = master(s)
    write_wav(opts.output, mix)
    print(f'{opts.output.name}: {len(mix)} stereo frames, {len(mix) / SR:.3f} s.')
    print(f'Sample peak {20 * np.log10(abs(mix).max()):.2f} dBFS.')


if __name__ == '__main__':
    main()
