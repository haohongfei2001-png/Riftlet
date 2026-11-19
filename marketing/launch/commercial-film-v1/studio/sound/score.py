#!/usr/bin/env python3
"""Riftlet — original chamber/electronic score and editorial foley. Python + NumPy."""
import argparse
import math
import wave
from pathlib import Path
import numpy as np

SR = 48000
TAU = 2 * math.pi
SEED = 20261114


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def time(seconds):
    return np.arange(round(SR * seconds)) / SR


def edge(t, a, r):
    return np.minimum(1, np.maximum(0, t / a)) * np.minimum(1, np.maximum(0, (t[-1] - t) / r))


def colored(n, low, high, rng):
    """Unlooped, band-shaped noise, unity RMS in the passband."""
    size = 1 << (n + 1023).bit_length()
    w = np.fft.rfftfreq(size, 1 / SR)
    white = np.fft.rfft(rng.normal(0, 1, size))
    response = (w / np.sqrt(w * w + low * low)) ** 3 / (1 + (w / high) ** 6) ** 0.5
    x = np.fft.irfft(white * response, size)[512:512 + n]
    return x / max(0.001, np.sqrt(np.mean(x * x)))


class Session:
    def __init__(self, duration):
        self.duration = duration
        self.shape = (round(duration * SR), 2)
        self.rng = np.random.default_rng(SEED)
        self.tracks = {name: np.zeros(self.shape) for name in ('keys', 'bass', 'bow', 'pulse', 'foley')}

    def place(self, track, at, mono, gain=1, pan=0):
        start = round(at * SR)
        hi = min(len(mono), self.shape[0] - start)
        lo = max(0, -start)
        if hi <= lo:
            return
        position = (pan + 1) * math.pi / 4
        lane = self.tracks[track][start + lo:start + hi]
        lane[:, 0] += mono[lo:hi] * gain * math.cos(position)
        lane[:, 1] += mono[lo:hi] * gain * math.sin(position)

    def key(self, at, note, vel, length=0.90, pan=0, wood=0.30):
        """Felt strike on a detuned two-course bar. The two bodies beat as they decay."""
        t = time(length)
        f = hz(note) * self.rng.uniform(.9996, 1.0004)
        position = self.rng.uniform(.1, 1.95)
        base_time = .45 * (240 / f) ** .34
        src = np.zeros_like(t)
        for ratio, amplitude, rel in [(1, .72, 1.12), (2.002, .24, .56), (3.009, .13, .37), (4.025, .055, .23), (6.78, wood * .36, .10), (10.3, wood * .12, .06)]:
            phase = TAU * ratio * f * t
            src += amplitude * (np.sin(phase + position) + .49 * np.sin(phase * 1.00165 + .91 * position)) * np.exp(-t / (base_time * rel))
        src *= (1 - np.exp(-t / .004)) * edge(t, .001, min(.15, length * .42))
        impact = colored(len(t), 900, 3200, self.rng) * np.exp(-t / .008) * (1 - np.exp(-t / .0014))
        self.place('keys', at, src + .10 * wood * impact, vel, pan)

    def bass(self, at, note, vel, length):
        t = time(length)
        f = hz(note)
        phase = TAU * f * (t + .00032 * (1 - np.exp(-t / .016)))
        body = .73 * np.sin(phase) + .32 * np.sin(2 * phase + .18) * np.exp(-t / .44) + .13 * np.sin(3 * phase + .4) * np.exp(-t / .22) + .04 * np.sin(5 * phase + .5) * np.exp(-t / .10)
        env = (1 - np.exp(-t / .013)) * np.exp(-t / .43) * edge(t, .001, min(.115, length * .52))
        self.place('bass', at, body * env, vel, -.065)

    def bow(self, at, notes, length, gain):
        """Small bowed ensemble, staggered breaths, different formants and bow release."""
        for note, pan, onset in zip(notes, [-.40, .27, -.10], [0, .038, .081]):
            t = time(length - onset)
            f = hz(note)
            vibrato = self.rng.uniform(4.6, 5.15)
            phase = TAU * f * t + .0018 * f / vibrato * np.sin(TAU * vibrato * t + self.rng.uniform(0, TAU))
            src = np.zeros_like(t)
            for h in range(1, 9):
                fn = h * f
                formant = .5 + .55 * np.exp(-((fn - 590) / 300) ** 2) + .22 * np.exp(-((fn - 1520) / 380) ** 2)
                src += formant * (1 + .17 * np.cos(h * 1.4)) * np.sin(h * phase + .13 * h) / h ** 1.14
            scrape = .028 * colored(len(t), 510, 1920, self.rng)
            env = (1 - np.exp(-t / .145)) * (.71 + .29 * np.sin(math.pi * t / t[-1]) ** 2) * edge(t, .13, min(.60, length * .54))
            self.place('bow', at + onset, (src + scrape) * env, gain, pan)

    def drum(self, at, kind, vel, pan=0):
        rng = self.rng
        if kind == 'heel':
            t = time(.31)
            phase = TAU * (73 * t + 2.1 * (1 - np.exp(-t / .025)))
            x = (.70 * np.sin(phase) + .22 * np.sin(phase * 1.46 + .7) * np.exp(-t / .047)) * np.exp(-t / .061)
            x += .15 * colored(len(t), 380, 1420, rng) * np.exp(-t / .011)
        elif kind == 'rim':
            t = time(.19)
            x = sum(v * np.sin(TAU * f * t) * np.exp(-t / d) for f, v, d in [(605, .32, .028), (898, .26, .022), (1324, .20, .013), (2740, .11, .007)])
            x += .23 * colored(len(t), 1000, 3900, rng) * np.exp(-t / .009)
        else:
            t = time(.13)
            x = colored(len(t), 1400, 6800, rng) * np.exp(-t / .018) * .43
        self.place('pulse', at, x * edge(t, .0015, .012), vel, pan)

    def button(self, at, vel, pan=0, mouse=False):
        for offset, g, f in [(0, 1, 1300 if mouse else 780), (.019 if mouse else .043, .46, 1880 if mouse else 1140)]:
            t = time(.071)
            freq = f * self.rng.uniform(.9, 1.10)
            body = (.29 * np.sin(TAU * freq * t) * np.exp(-t / .0055) + .11 * np.sin(TAU * freq * .42 * t) * np.exp(-t / .012) + .05 * np.sin(TAU * freq * 2.33 * t) * np.exp(-t / .004))
            body += .39 * colored(len(t), 1280, 5400, self.rng) * np.exp(-t / .0035)
            self.place('foley', at + offset, body * edge(t, .0005, .007), vel * g, pan)

    def shutter(self, at, gain):
        # Overlapping blade movement and two fine stops: no platform sound recording.
        for off, f, v, decay in [(0, 2750, .50, .009), (.014, 1830, .35, .013), (.046, 1130, .67, .017), (.077, 590, .23, .023)]:
            t = time(.16)
            x = .51 * colored(len(t), f * .43, f * 1.75, self.rng) + .38 * np.sin(TAU * f * t) * np.exp(-t / .004) + .20 * np.sin(TAU * f * .44 * t) * np.exp(-t / .020)
            self.place('foley', at + off, x * np.exp(-t / decay) * edge(t, .0007, .015), gain * v, -.10)

    def arrival(self, at, gain, note):
        # Short leather-covered landing with warm, quickly muted resonances.
        t = time(.28)
        f = hz(note)
        phase = TAU * (f * t + .35 * (1 - np.exp(-t / .022)))
        x = (.61 * np.sin(phase) * np.exp(-t / .043) + .23 * np.sin(phase * 2.14) * np.exp(-t / .024) + .16 * colored(len(t), 710, 2050, self.rng) * np.exp(-t / .009))
        self.place('foley', at, x * edge(t, .0025, .02), gain, .31)

    def attached(self, at):
        # Short contact plus two tuned sympathetic bodies inside one editorial accent.
        self.arrival(at, .285, 62)
        self.key(at + .024, 74, .175, .59, -.07, .15)
        self.key(at + .081, 81, .106, .72, .10, .11)

    def keys(self, start, notes):
        for delay, note, vel, length, pan in notes:
            self.key(start + delay, note, vel, length, pan)


def opening(s):
    # Interrupted thought: only one close instrument, a low answer, and a typing gesture.
    s.keys(0, [(.055, 62, .32, .79, -.21), (.36, 64, .22, .61, -.08), (.85, 69, .29, 1.2, .18), (1.65, 57, .135, .63, -.35), (2.31, 65, .26, .78, -.09), (2.58, 64, .19, .57, .09), (3.11, 59, .25, .79, -.31), (3.39, 62, .16, .78, .15)])
    s.bass(.055, 38, .47, 1.0)
    s.bass(2.31, 43, .39, .80)
    s.bow(1.1, [57, 64], 2.4, .057)
    for t in [.20, .352, .56, 1.05, 1.177, 1.36]:
        s.button(t, .105, -.18)
    for at, kind, v, p in [(1.82, 'sand', .064, .4), (2.05, 'sand', .10, .32), (2.32, 'heel', .19, 0), (2.86, 'rim', .12, .19), (3.42, 'sand', .1, .37), (3.69, 'rim', .14, .00)]:
        s.drum(at, kind, v, p)


def moving(s):
    # Eight asymmetrical two-beat cells. The empty cells frame operating sounds.
    for at, base, high, accents in [(4.02, 38, 69, (0, 3)), (5.12, 38, 65, ()), (6.22, 41, 69, (0, 2)), (7.32, 43, 71, (0, 3)), (8.42, 43, 67, ()), (9.52, 40, 67, (0, 2, 3)), (10.62, 45, 71, (0, 3)), (11.72, 45, 69, (0, 2))]:
        s.bass(at, base, .43, .52)
        for i in accents:
            s.key(at + [.012, .281, .552, .832][i], high if i == 0 else high - (2 if i == 2 else 5), [.265, .16, .19, .145][i], .50, -.22 if i == 0 else .28, .46)
        if accents:
            s.drum(at, 'heel', .285, -.10)
            s.drum(at + .558, 'rim', .23, .16)
            for d, v in [(.284, .094), (.827, .132)]:
                s.drum(at + d, 'sand', v, .46)
    s.bow(5.72, [57, 64], 2.13, .052)
    s.bow(8.70, [59, 64, 67], 3.17, .067)
    s.key(12.31, 64, .19, .40, .10)
    s.shutter(5.10, .73)
    s.arrival(5.55, .47, 57)
    s.shutter(8.10, .69)
    s.arrival(8.55, .48, 59)
    s.button(13.20, .79, .24, mouse=True)
    s.attached(13.45)


def continuation(s):
    s.bass(13.46, 38, .51, 1.11)
    s.bow(13.66, [57, 64, 65], 2.00, .070)
    for at, root, a, b, c in [(14.10, 38, 62, 64, 69), (16.20, 43, 62, 67, 71), (18.30, 40, 60, 64, 67), (20.40, 45, 62, 64, 69)]:
        s.bass(at + .01, root, .46, .76)
        s.bass(at + 1.34, root + 7, .30, .38)
        for delay, note, amp, pan in [(.015, a, .23, -.27), (.276, b, .14, .06), (.79, c, .266, .22), (1.183, b, .135, -.06), (1.60, c - 5, .18, .18), (1.87, a, .13, -.27)]:
            s.key(at + delay, note, amp, .66, pan, .32)
        for dt, kind, gain, pan in [(0, 'heel', .32, -.07), (.536, 'rim', .24, .18), (.806, 'sand', .08, .44), (1.075, 'heel', .21, -.09), (1.34, 'rim', .11, .08), (1.60, 'rim', .21, .17), (1.866, 'sand', .095, .42)]:
            s.drum(at + dt, kind, gain, pan)
    s.bow(16.42, [55, 62, 71], 1.55, .068)
    s.bow(18.36, [55, 60, 64], 1.93, .064)
    s.bow(20.53, [57, 62, 64], 1.70, .060)
    for at, vel in [(17.80,.18), (17.96,.15), (18.084,.19), (18.283,.15), (18.64,.21), (18.80,.14), (18.926,.19), (19.20,.14), (19.31,.17), (19.65,.20), (20.01,.17), (20.17,.15), (20.42,.17), (20.62,.24)]:
        s.button(at, vel, s.rng.uniform(-.17, .05))


def endcard(s, at):
    s.bass(at, 38, .48, 1.35)
    s.keys(at, [(.02, 57, .18, 1.5, -.36), (.036, 62, .20, 1.30, -.15), (.070, 65, .17, 1.3, .14), (.089, 71, .115, 1.52, .30), (1.01, 69, .20, 1.04, .22), (1.80, 64, .177, .73, .11)])
    s.bow(at + .04, [57, 65, 71], 2.15, .071)
    # Brand signature. Whole step up, perfect fourth up. Last note rings over a warm D6/9.
    s.key(at + 2.62, 62, .33, 1.02, -.16, .16)
    s.key(at + 3.00, 64, .24, .92, -.06, .16)
    s.key(at + 3.62, 69, .335, 2.66, .13, .16)
    s.bass(at + 3.62, 38, .385, 1.44)
    s.bow(at + 3.57, [50, 59, 65], 2.97, .063)
    s.key(at + 3.65, 74, .105, 2.26, .34, .12)


def room(x, scale=1):
    # Sparse asymmetrical early reflections from one small, damped room.
    out = x.copy()
    for ms, gain, flip in [(13.6, .092, False), (20.9, .075, True), (34.3, .054, True), (48.6, .043, False), (71.1, .029, True), (105.2, .018, False), (151.4, .010, True), (218.6, .006, False)]:
        d = round(ms * SR / 1000)
        src = x[:-d, ::-1] if flip else x[:-d]
        out[d:] += src * scale * gain
    return out


def master(s):
    musical = room(s.tracks['keys']) + room(s.tracks['bow'], .85) + room(s.tracks['pulse'], .50) + room(s.tracks['bass'], .18)
    fx = room(s.tracks['foley'], .31)
    bed = np.zeros(s.shape)
    for ch in range(2):
        bed[:, ch] = .00085 * colored(s.shape[0], 110, 830, s.rng)
    envelope = np.minimum(1, time(s.duration) / .045) * np.minimum(1, np.maximum(0, (s.duration - .14 - time(s.duration)) / .56))
    mixed = (musical + fx + bed) * envelope[:, None]
    return np.tanh(1.39 * mixed) * .95


def write_wav(path, data):
    # Signed little-endian 24-bit PCM, dithered once at the final quantization.
    noise = np.random.default_rng(8711)
    dither = noise.random(data.shape) - noise.random(data.shape)
    q = np.clip(np.rint(data * 8388607 + .5 * dither), -8388608, 8388607).astype('<i4')
    with wave.open(str(path), 'wb') as target:
        target.setparams((2, 3, SR, len(data), 'NONE', 'PCM'))
        target.writeframes(q.view(np.uint8).reshape(-1, 4)[:, :3].copy().tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    opts = parser.parse_args()
    s = Session(30)
    opening(s)
    moving(s)
    continuation(s)
    endcard(s, 23.)
    mix = master(s)
    write_wav(opts.output, mix)
    print(f'{opts.output.name}  {len(mix) / SR:.2f} s  48 kHz stereo 24-bit PCM')
    print(f'Sample peak {20 * np.log10(abs(mix).max()):.2f} dBFS. RMS {20 * np.log10(np.sqrt((mix ** 2).mean())):.2f} dBFS.')


if __name__ == '__main__':
    main()
