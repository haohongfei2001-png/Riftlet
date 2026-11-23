"""Original 20 s instrumental and foley. Requires Python 3 and NumPy."""

from pathlib import Path
import argparse
import wave
import numpy as np

RATE = 48000
DURATION = 20
BPM = 120
BEAT = 60 / BPM
TAU = 2 * np.pi
RNG = np.random.default_rng(112309)
NS = DURATION * RATE


def time(length):
    return np.arange(round(RATE * length), dtype=np.float64) / RATE


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def put(bus, at, signal, gain, pan=0.0):
    start = round(at * RATE)
    n = min(len(signal), len(bus) - start)
    if n <= 0:
        return
    angle = (1 + pan) * np.pi / 4
    bus[start : start + n] += gain * signal[:n, None] * np.array([np.cos(angle), np.sin(angle)])


def ring(note, length, timbre):
    t = time(length)
    f = hz(note)
    # A struck string and a felted tine have different transient slopes.
    if timbre == "pluck":
        weights = (1, 0.38, 0.22, 0.09, 0.065, 0.034)
        decays = (0.44, 0.24, 0.17, 0.12, 0.092, 0.07)
        sound = np.zeros_like(t)
        for i, (a, d) in enumerate(zip(weights, decays), 1):
            freq = f * i * (1 + 0.00031 * i * i)
            sound += a * np.sin(TAU * freq * t + 0.23 * i) * np.exp(-t / d)
        sound *= 1 - np.exp(-t / 0.002)
        contact = RNG.normal(0, 1, len(t))
        sound += 0.052 * np.diff(contact, prepend=0) * np.exp(-t / 0.005)
    elif timbre == "tine":
        # A short-lived modulation index models the metallic onset of a tine.
        mod = 0.96 * np.exp(-t / 0.14) * np.sin(TAU * t * f * 2.005)
        sound = np.sin(TAU * f * t + mod) + 0.12 * np.sin(TAU * 2 * t * f + mod * 0.3)
        sound += 0.25 * np.sin(TAU * f * 1.002 * t + 0.11)
        sound *= (1 - np.exp(-t / 0.012)) * np.exp(-t / 0.71)
    else:
        sound = np.sin(TAU * f * t) + 0.24 * np.sin(TAU * 2 * f * t) + 0.09 * np.sin(TAU * 3 * f * t)
        sound *= (1 - np.exp(-t / 0.012)) * np.exp(-t / 0.34)
    fade = min(round(0.045 * RATE), len(t) // 2)
    sound[-fade:] *= np.linspace(1, 0, fade) ** 2
    return sound


def keytap(flavour):
    t = time(0.072)
    noise = RNG.normal(0, 1, len(t))
    bright = np.diff(noise, prepend=0)
    return (
        np.sin(TAU * (1240 + 80 * flavour) * t) * np.exp(-t / 0.0045)
        + 0.53 * np.sin(TAU * (520 + 22 * flavour) * t) * np.exp(-t / 0.012)
        + 0.52 * bright * np.exp(-t / 0.0018)
    ) * (1 - np.exp(-t / 0.00048))


def room(stereo):
    wet = np.zeros_like(stereo)
    for delay, gain, swap in (
        (0.029, 0.12, False),
        (0.048, 0.09, True),
        (0.073, 0.075, True),
        (0.121, 0.043, False),
        (0.173, 0.026, True),
        (0.244, 0.016, False),
    ):
        n = round(delay * RATE)
        wet[n:] += gain * (stereo[:-n, ::-1] if swap else stereo[:-n])
    return stereo + wet


def compose():
    piano = np.zeros((NS, 2))
    lead = np.zeros_like(piano)
    rhythm = np.zeros_like(piano)
    effects = np.zeros_like(piano)
    # A five-note cell arcs up and folds back; recurrence marks the resumed draft.
    # Times are beats within 2 s bars, with room for the physical clicks.
    cell = [(0, 76, 0.68), (0.75, 79, 0.48), (1.50, 83, 0.61), (2.75, 81, 0.47), (3.38, 76, 0.51)]
    voicings = [
        (41, (60, 64, 67, 69)),
        (43, (59, 62, 67, 69)),
        (45, (60, 64, 67, 71)),
        (40, (59, 62, 67, 71)),
        (41, (57, 60, 64, 67)),
        (43, (59, 62, 64, 69)),
        (45, (60, 64, 67, 71)),
        (43, (59, 62, 67, 69)),
        (41, (57, 60, 64, 67)),
        (48, (59, 62, 64, 67)),
    ]
    for bar, (root, chord) in enumerate(voicings):
        start = bar * 2.0
        for j, pitch in enumerate(chord):
            offset = (0.23, 0.26, 0.30, 0.34)[j] if bar % 2 == 0 else (0.04, 0.075, 0.11, 0.16)[j]
            vel = 0.093 if bar not in (5, 6, 9) else 0.06
            put(piano, start + offset, ring(pitch, 1.34, "tine"), vel, (j - 1.5) * 0.25)
        if bar in (0, 3, 4, 6, 7):
            for j, note in enumerate(chord[1::2]):
                put(piano, start + 1.38 + j * 0.026, ring(note, 0.46, "tine"), 0.055, -0.28 + j * 0.41)
        if bar < 9:
            for b, note, vel, ln in (
                (0, root, 0.41, 0.5),
                (1.50, root + 12, 0.14, 0.28),
                (2.55, root + 7, 0.20, 0.39),
            ):
                if bar in (5, 6) and b == 1.50:
                    continue
                put(rhythm, start + b * BEAT, ring(note, ln, "bass"), vel, -0.04)
        if bar in (0, 3, 7):
            for b, note, vel in cell:
                put(lead, start + b * BEAT, ring(note, 0.64, "pluck"), vel * 0.27, -0.2 + b * 0.11)
        elif bar in (2, 4):
            for b, note in ((1.3, 74), (2.03, 76), (3.53, 71)):
                put(lead, start + b * BEAT, ring(note, 0.55, "pluck"), 0.12, 0.20)
        # Closely miked brush and soft foot pulse; fret-like syncopations.
        for b in (0, 2.5):
            if bar == 9 or (bar >= 5 and b == 2.5):
                continue
            t = time(0.20)
            pulse = np.sin(TAU * (49 * t + 1.96 * (1 - np.exp(-t / 0.024)))) * np.exp(-t / 0.068)
            pulse *= 1 - np.exp(-t / 0.0014)
            put(rhythm, start + b * BEAT, pulse, 0.27, -0.05)
        if bar < 9:
            for b, vol in ((1, 0.055), (3, 0.067), (3.5, 0.020)):
                t = time(0.065)
                n = RNG.normal(0, 1, len(t))
                airy = np.diff(n, prepend=0) * np.exp(-t / 0.012)
                wood = np.sin(TAU * 753 * t) * np.exp(-t / 0.006)
                put(rhythm, start + b * BEAT + 0.008, 0.38 * airy + wood, vol, 0.22 - (b % 2) * 0.31)
        if bar < 8:
            for beat in (0.5, 1.55, 2.5, 3.55):
                t = time(0.09)
                n = RNG.normal(0, 1, len(t))
                grain = np.diff(n, prepend=0)
                put(rhythm, start + beat * BEAT, grain * np.exp(-t / 0.011), 0.017, 0.36)
    # The final writing phrase and wordmark share a cadence resolved to E.
    for at, note, gain in (
        (16.00, 72, 0.14),
        (16.38, 76, 0.16),
        (16.76, 79, 0.15),
        (17.05, 83, 0.21),
        (17.39, 81, 0.11),
        (17.80, 79, 0.14),
        (18.45, 76, 0.16),
    ):
        put(lead, at, ring(note, 1.26, "tine"), gain, 0.1)
    put(rhythm, 17.05, ring(48, 1.2, "bass"), 0.30, 0.0)
    # Designed foley. Each sound is synthesized here, with no capture of user data.
    t = time(0.13)
    noise = RNG.normal(0, 1, len(t))
    spring = 0.54 * np.sin(TAU * t * 1035) * np.exp(-t / 0.006) + 0.40 * np.diff(noise, prepend=0) * np.exp(
        -t / 0.011
    )
    put(effects, 2.73, spring, 0.24, -0.20)
    put(effects, 2.753, keytap(-2), 0.12, -0.12)
    put(effects, 3.16, ring(81, 0.26, "pluck"), 0.105, 0.43)
    # Two quieter arrivals and a second click accompany the appearance comparison.
    put(effects, 7.03, ring(81, 0.22, "pluck"), 0.076, -0.17)
    put(effects, 7.69, ring(83, 0.22, "pluck"), 0.070, 0.17)
    put(effects, 8.82, keytap(1), 0.19, 0.08)
    put(effects, 8.97, ring(79, 0.23, "tine"), 0.065, 0.08)
    put(effects, 4.33, keytap(1), 0.31, 0.38)
    put(effects, 4.37, keytap(4), 0.067, 0.32)
    for a, n, g in ((4.80, 74, 0.14), (4.854, 79, 0.14)):
        put(effects, a, ring(n, 0.37, "tine"), g, -0.13)
    for j, a in enumerate(
        (
            11.06,
            11.21,
            11.42,
            11.58,
            11.69,
            12.06,
            12.28,
            12.44,
            12.87,
            13.03,
            13.29,
            13.63,
            13.77,
            14.07,
            14.28,
        )
    ):
        put(effects, a, keytap((j * 5) % 7), (0.055, 0.071, 0.037, 0.062)[j % 4], -0.12 + 0.08 * (j % 4))
    put(lead, 15.10, ring(76, 0.73, "pluck"), 0.16, -0.10)
    music = room(piano) + room(lead) + rhythm
    # Dip the score very slightly around the three principal interaction accents.
    t = np.arange(NS) / RATE
    duck = np.ones(NS)
    for at, depth, length in ((2.73, 0.23, 0.095), (4.33, 0.40, 0.093), (4.80, 0.23, 0.09)):
        duck -= depth * np.exp(-0.5 * ((t - at) / length) ** 2)
    mix = music * duck[:, None] + effects
    # Gentle analogue saturation reduces the crest factor of simultaneous notes.
    mix = np.tanh(1.25 * mix)
    mix[:240] *= np.sin(np.linspace(0, np.pi / 2, 240))[:, None] ** 2
    release = t > 19.22
    mix[release] *= np.cos((t[release] - 19.22) / (0.78) * np.pi / 2)[:, None] ** 2
    return mix


def save(path, sound, level):
    sound = sound * level
    assert np.max(np.abs(sound)) < 1.0
    a = np.rint(sound * (2**23 - 1)).astype("<i4").reshape(-1)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(3)
        wav.setframerate(RATE)
        wav.writeframes(a.view("u1").reshape(-1, 4)[:, :3].copy().tobytes())
    print(
        f"{path.name}  {len(sound) / RATE:.3f}s  sample peak {20 * np.log10(np.max(np.abs(sound))):.2f} dBFS"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path(__file__).with_name("score.wav"))
    args = parser.parse_args()
    save(args.out, compose(), 1.105)
