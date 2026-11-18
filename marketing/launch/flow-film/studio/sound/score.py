"""Build the two original Riftlet soundtracks. Requires Python and NumPy."""
import argparse
import math
import wave
from pathlib import Path

import numpy as np


SR = 48_000
TAU = 2 * math.pi

# Picture cues are seconds from the first frame, including the slate-free opening.
MAIN = dict(duration=24, capture=[2.30, 3.63, 4.97, 10.30, 11.63, 12.97],
            select=[6.60, 15.00, 16.55], attach=[6.83, 15.23, 16.78],
            settle=[7.10, 15.50, 17.05], typing=(17.25, 20.25), signature=21.35)
SHORT = dict(duration=15, capture=[1.00, 1.90, 2.80, 6.20, 7.12, 8.00],
             select=[3.83, 9.00, 10.15], attach=[4.06, 9.23, 10.38],
             settle=[4.33, 9.50, 10.65], typing=(10.80, 12.75), signature=13.25)


def timebase(seconds):
    return np.arange(round(SR*seconds), dtype=np.float64)/SR


def hz(midi):
    return 440*2**((midi-69)/12)


def fade_edges(signal, attack=.001, release=.008):
    n = min(len(signal), max(1, round(attack*SR)))
    signal[:n] *= np.sin(np.linspace(0, math.pi/2, n))**2
    n = min(len(signal), max(1, round(release*SR)))
    signal[-n:] *= np.cos(np.linspace(0, math.pi/2, n))**2
    return signal


def grain(rng, t, lo, hi):
    """A new band-limited excitation for each brush, key or membrane."""
    freqs = np.fft.rfftfreq(len(t), 1/SR)
    response = (1 - np.exp(-(freqs/lo)**4))*np.exp(-(freqs/hi)**4)
    samples = np.fft.irfft(np.fft.rfft(rng.normal(size=len(t)))*response, n=len(t))
    return samples/max(1.e-6, np.sqrt(np.mean(samples*samples)))


def tine(note, length, bright=1.):
    # The tine and its resonator have different damping times. Their difference
    # makes the long Rhodes notes bloom after the initial mallet strike.
    t = timebase(length)
    p = TAU*hz(note)*t
    body = np.sin(p + .31*np.exp(-9*t)*np.sin(2*p))
    body += .26*np.sin(2.002*p+.2)*np.exp(-4*t)
    body += .14*np.sin(3*p)*np.exp(-8*t)
    strike = bright*.22*np.sin(6.974*p+.1)*np.exp(-25*t)
    return fade_edges((body*np.exp(-3.3*t/length)+strike)*.81, .006, min(.12, length/3))


def tap(note, length=.24):
    # Short maple block; the first overtone is a bending mode rather than an octave.
    t = timebase(length)
    p = TAU*hz(note)*t
    return fade_edges(.76*np.sin(p)*np.exp(-23*t)+.30*np.sin(2.63*p+.7)*np.exp(-47*t)
                      +.14*np.sin(4.12*p+.3)*np.exp(-70*t), .0017, .018)


def bass(note, length, offbeat=False):
    t = timebase(length)
    p = TAU*hz(note)*t + .15*(1-np.exp(-30*t))
    y = np.sin(p)+.31*np.sin(2*p+.12)*np.exp(-8*t)+.13*np.sin(3*p)*np.exp(-11*t)
    y *= (.75+.25*np.exp(-10*t))*np.exp(-1.8*t/length)
    return fade_edges(np.tanh(1.45*y)*.88, .006 if offbeat else .012, .044)


def kick(rng):
    t = timebase(.26)
    phase = TAU*(46*t + 2.8*(1-np.exp(-25*t)) + .50*(1-np.exp(-105*t)))
    y = np.sin(phase)*np.exp(-16*t)+.09*grain(rng,t,480,3200)*np.exp(-250*t)
    return fade_edges(y, .001, .020)


def side_stick(rng, ghost=False):
    t = timebase(.125)
    stick = .43*np.sin(TAU*675*t)*np.exp(-82*t)+.2*np.sin(TAU*1103*t)*np.exp(-97*t)
    rim = .65*np.sin(TAU*211*t + .5*np.exp(-86*t))*np.exp(-55*t)
    brush = .45*grain(rng, t, 740, 5100 if not ghost else 3550)*np.exp(-43*t)
    return fade_edges(stick+rim+brush, .0012, .010)


def hat(rng, length, strength):
    t = timebase(length)
    y = grain(rng,t,4500,10500)*np.exp(-4.8*t/length)
    y += .16*np.sin(TAU*6217*t + .9*np.sin(TAU*1793*t))*np.exp(-7*t/length)
    return fade_edges(y*strength,.0016,.008)


def shutter(rng, narrow):
    t = timebase(.125)
    # Two nonidentical blades, followed by the tiny paper-like return.
    y = grain(rng,t,780,6800)*np.exp(-150*t)
    y += .35*np.sin(TAU*765*t + 1.1*np.exp(-80*t))*np.exp(-97*t)
    d = np.maximum(0,t-.033)
    y += (t>.033)*(.51*grain(rng,t,1100,4600)*np.exp(-85*d)
                   +.22*np.sin(TAU*1115*d)*np.exp(-80*d))
    if narrow:
        y += .14*np.sin(TAU*(1370*t+360*t*t))*np.exp(-48*t)
    return fade_edges(y, .0014, .012)


def key(rng, size):
    t = timebase(.070)
    f = rng.uniform(520,800)
    e = np.exp(-t*rng.uniform(120,180))
    y = e*(.40*grain(rng,t,1100,5200)+.67*np.sin(TAU*f*t))
    y += .32*np.sin(TAU*f*.64*t+.4)*np.exp(-78*t)
    return fade_edges(y*size, .0008,.010)


def place(bus, signal, seconds, gain, pan=0.):
    start = round(seconds*SR)
    if not 0 <= start < len(bus):
        return
    mono = signal[:min(len(signal),len(bus)-start)]*gain
    angle = (pan+1)*math.pi/4
    bus[start:start+len(mono),0] += math.cos(angle)*mono
    bus[start:start+len(mono),1] += math.sin(angle)*mono


def room(bus, rng):
    # Deterministic stereo room: short asymmetric early reflections and diffuse,
    # damped tails. No external sample or impulse response.
    output = bus.copy()
    for channel in range(2):
        dry = bus[:,channel]*.82 + bus[:,1-channel]*.18
        impulse = np.zeros(round(.58*SR))
        for delay,amp in ((.024,.106),(.043,.072),(.068,-.049),(.084,.041),(.123,.024)):
            impulse[round((delay+.0021*channel)*SR)] = amp
        positions = rng.choice(np.arange(round(.041*SR),len(impulse)-5),1800,replace=False)
        impulse[positions] += rng.choice([-1,1],len(positions))*.012*np.exp(-positions/(.117*SR))
        impulse = np.convolve(impulse, [0.13,.28,.31,.19,.09])
        n = 1 << (len(bus)+len(impulse)-2).bit_length()
        tail = np.fft.irfft(np.fft.rfft(dry,n)*np.fft.rfft(impulse,n),n)
        output[:,channel] += tail[:len(bus)]
    return output


def k_loudness(audio):
    # ITU-R BS.1770 K filter coefficients for 48 kHz. Frequency-domain evaluation
    # with zero padding keeps the implementation independent of SciPy.
    b1 = [1.53512485958697,-2.69169618940638,1.19839281085285]
    a1 = [1.,-1.69065929318241,.73248077421585]
    b2 = [1.,-2.,1.]
    a2 = [1.,-1.99004745483398,.99007225036621]
    n = 1 << (len(audio)+SR-1).bit_length()
    z = np.exp(-1j*TAU*np.fft.rfftfreq(n))
    poly = lambda c: c[0]+c[1]*z+c[2]*z*z
    transfer = poly(b1)*poly(b2)/(poly(a1)*poly(a2))
    y = np.fft.irfft(np.fft.rfft(audio,n,axis=0)*transfer[:,None], n, axis=0)[:len(audio)]
    power = np.sum(y*y,axis=1)
    ms = np.array([power[i:i+19200].mean() for i in range(0,len(power)-19199,4800)])
    absolute = ms[ms>10**((-70+.691)/10)]
    gated = absolute[absolute>absolute.mean()*.1]
    return -.691 + 10*np.log10(gated.mean())


def compose(spec, short=False):
    rng = np.random.default_rng(67615 if short else 67624)
    duration = spec['duration']
    beat = 60/(133.333333 if short else 135)
    rhythm, pitched, effects = [np.zeros((round(duration*SR),2)) for _ in range(3)]
    signature = spec['signature']
    # Dmaj9 -> Bm11 -> G6/9 -> A6sus. Melody uses a three-note cell that
    # returns resolved under the wordmark. Durations leave pocket for real clicks.
    voicings = [(38,[54,57,61,64]),(35,[54,57,62,64]),
                (31,[54,57,59,64]),(33,[52,57,59,62])]
    motif = [(0,73),(.75,69),(1.50,66),(2.75,71)]
    bar = 0
    while (bar*4*beat) < signature-.14:
        start = bar*4*beat
        root,chord = voicings[bar%4]
        def event(bus, signal, off, gain, pan=0):
            when = start+off*beat
            if when < signature-.09:
                place(bus,signal,when,gain,pan)
        # Syncopated low line, relaxed against a close, sixteenth-note top.
        for off,length,step,vel in [(0,1.35,0,.82),(1.75,.45,12,.52),(2.5,.88,0,.83),(3.65,.25,7,.47)]:
            if bar%2 and off==1.75: continue
            event(pitched,bass(root+step,length*beat,off!=0),off,.36*vel)
        for off,amp in ([(0,1),(1.5,.62),(2.75,.88)] if bar%2==0 else [(0,1),(2.25,.76),(3.5,.5)]):
            event(rhythm,kick(rng),off,.55*amp)
        for off,amp in [(1,.84),(3,.97),(3.77,.23)]:
            if bar==0 and off==3.77: continue
            event(rhythm,side_stick(rng,amp<.4),off+.022,.274*amp,-.10)
        for slot in range(8):
            off=slot*.5 + (.044 if slot%2 else 0)
            if (bar+slot)%7==5: continue
            length=.11 if slot==7 and bar%2 else .045
            event(rhythm,hat(rng,length,.64 if slot%2 else 1),off,
                  .079 if slot%4 else .10, .35 if slot%2 else -.27)
        for off,gain,length in [(.13,.18,1.19),(2.02,.135,.75)]:
            if bar%3==1 and off>1: continue
            for i,note in enumerate(chord):
                event(pitched,tine(note,length/1.17),off+i*.018,gain*(1-.065*i),
                      -.41+.24*i)
        for i,(off,note) in enumerate(motif):
            # First chapter on maple, second chapter answered an octave higher
            # by a small tine. The signature has the same descending interval.
            if (i+bar)%4==3: continue
            shift = [0,-2,0,-2][bar%4]
            second = start >= spec['capture'][3]-.4
            sound = tine(note+shift,.40,.65) if second else tap(note+shift,.22)
            event(pitched,sound,off+(.25 if bar%2 else 0),.13*(1-.09*i),.28 if i%2 else -.23)
        bar += 1

    for i,at in enumerate(spec['capture']):
        place(effects,shutter(rng,i>=3),at,.41,-.27)
        place(effects,tap([76,78,81][i%3],.13),at+.105,.155,.27)
    for at in spec['select']:
        place(effects,key(rng,1),at,.65,.22)
        place(effects,tap(66,.14),at+.007,.23,.20)
    for at in spec['attach']:
        place(effects,tine(81,.33),at,.197,-.14)
        place(effects,tine(85,.24),at+.034,.107,-.19)
    for at in spec['settle']:
        t=timebase(.108)
        y=grain(rng,t,680,3000)*np.sin(np.pi*t/.108)**2
        place(effects,y,at,.060,.29)
    at,stop=spec['typing']
    i=0
    while at < stop:
        place(effects,key(rng,rng.uniform(.36,.87)),at,.248,rng.uniform(-.38,.24))
        at += rng.uniform(.073,.170) + (.19 if i%7==3 else 0)
        i += 1

    # Two dry notes and a held sixth colour the end card. The last low string
    # decays under the final frame, with a light brush to carry the motion.
    for off,note in [(0,78),(.17,73),(.41,81)]:
        place(pitched,tine(note,.82),signature+off,.285,.13-off)
    tail=min(duration-signature-.15,2.35)
    for i,note in enumerate([50,57,61,66,71]):
        place(pitched,tine(note,tail,.33),signature+.015*i,.19,-.4+.20*i)
    place(pitched,bass(38,min(1.50,duration-signature-.18)),signature+.03,.36)
    place(rhythm,kick(rng),signature,.48)
    place(rhythm,hat(rng,.31,.7),signature+.024,.08,.42)

    bed=room(pitched,rng)+rhythm
    # Briefly clear the percussive spectrum for the cut and point. Continuous
    # envelopes keep the bed in motion, also during the concentrated typing.
    t=timebase(duration)
    gain=np.ones(len(t))
    for at in spec['capture']+spec['select']+spec['attach']:
        gain -= .22*np.exp(-((t-(at+.016))/.058)**2)
    bed *= gain[:,None]
    mix=bed+room(effects,rng)
    mix=1.22*np.tanh(mix/1.22)
    mix[:round(.006*SR)]*=np.linspace(0,1,round(.006*SR))[:,None]
    mix[-round(.155*SR):]*=np.linspace(1,0,round(.155*SR))[:,None]
    mix *= 10**((-15.65-k_loudness(mix))/20)
    # Stereo-linked 1 ms detection, a short look-ahead and a 50–90 ms
    # release. Rare shutter peaks do not set the level of the entire song.
    block = 48
    peaks = np.max(np.abs(mix.reshape(-1,block,2)),axis=(1,2))
    gain_db = np.minimum(0., -1.82-20*np.log10(np.maximum(peaks,1.e-12)))
    gain_db = np.minimum(gain_db, np.r_[gain_db[1:],gain_db[-1]])
    for i in range(len(gain_db)-2,-1,-1):
        gain_db[i] = min(gain_db[i], gain_db[i+1]+.80)
    for i in range(1,len(gain_db)):
        gain_db[i] = min(gain_db[i], gain_db[i-1]+.08)
    env = np.interp(np.arange(len(mix))/block,np.arange(len(peaks)),gain_db)
    return mix * 10**(env[:,None]/20)


def write_wav(path, audio):
    # Little-endian 24-bit interleaved PCM without an extra package.
    values=np.rint(np.clip(audio,-1,1)*(2**23-1)).astype('<i4').reshape(-1)
    packed=values.view('u1').reshape(-1,4)[:,:3].copy()
    with wave.open(str(path),'wb') as file:
        file.setnchannels(2)
        file.setframerate(SR)
        file.setsampwidth(3)
        file.writeframes(packed.tobytes())


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',nargs='?',type=Path,default=Path(__file__).resolve().parent)
    args=parser.parse_args()
    args.output.mkdir(exist_ok=True,parents=True)
    for name,spec,short in [('master',MAIN,False),('vertical',SHORT,True)]:
        music=compose(spec,short)
        write_wav(args.output/f'{name}.wav',music)
        print(f'{name}: {len(music)/SR:.3f}s, {k_loudness(music):.2f} LUFS, '
              f'{20*np.log10(np.max(np.abs(music))):.2f} dBFS peak')
