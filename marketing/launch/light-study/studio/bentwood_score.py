"""Original score for the bentwood cut: felt keys, timber taps and a short rhythmic figure."""
import wave
import numpy as np

def make_mix(path,fps,duration):
    rate=48000
    total=round(rate*duration)
    stereo=np.zeros((total,2),dtype='float64')
    rng=np.random.default_rng(1978)
    def place(at,samples,pan):
        j=round(at*rate); n=min(len(samples),total-j)
        if n>0: stereo[j:j+n]+=samples[:n,None]*np.array([np.cos((pan+1)*np.pi/4),np.sin((pan+1)*np.pi/4)])
    def note(at,f,level,tail,pan):
        t=np.arange(round((tail*5+.06)*rate))/rate
        env=(1-np.exp(-t/.009))*np.exp(-t/tail)
        sound=level*env*(np.sin(2*np.pi*f*t)+.30*np.sin(2*np.pi*2.003*f*t)*np.exp(-t/.53)+.08*np.sin(2*np.pi*f*4.01*t)*np.exp(-t/.17))
        place(at,sound,pan);place(at+.175,sound*.13,-pan)
    def tap(at,level,kind):
        t=np.arange(round(.12*rate))/rate
        dry=np.diff(rng.normal(0,.35,len(t)),prepend=0)*np.exp(-t/.005)
        thump=np.sin(2*np.pi*(kind+55*np.exp(-t/.023))*t)*np.exp(-t/.023)
        place(at,level*(dry+thump),-.22)
    for start,root in ((0,146.83),(5.2,130.81),(10.4,98),(15.6,123.47),(20.8,110),(26,146.83)):
        for k,interval in enumerate((1,1.5,2.5,2)):
            note(start+.26+k*.66,root*interval,.105 if k else .15,.52 if k else 1.35,(-.4,.22,.42,-.15)[k])
        note(start+.12,root/2,.17,1.65,0)
    for i in range(12):
        tap(5+i*.66,.07 if i%2 else .11,152 if i%2 else 108)
    for t in (.38,.59,.73,.88,1.05,8.30,8.35,10.95,18.58,20.85,21.23,21.51,22.18,22.66):tap(t,.145,242)
    for t,f in ((8.44,440),(11.03,587.33),(18.92,493.88),(19.13,739.99),(24.89,293.66),(25.55,440),(26.03,587.33)):
        note(t,f,.13,.8,.24)
    t=np.arange(total)/rate
    stereo*=np.clip(np.minimum(t/.05,(duration-t)/.80),0,1)[:,None]
    stereo*=.72/np.max(np.abs(stereo))
    with wave.open(str(path),'wb') as stream:
        stream.setparams((2,2,rate,0,'NONE','not compressed'))
        stream.writeframes((stereo*32767).astype('<i2').tobytes())
