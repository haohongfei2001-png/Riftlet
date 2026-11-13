"""Original miniature score: bowed chords, struck glass and paper-shutter transients."""
import wave
import numpy as np

RATE=48000


def write_score(path,duration,which):
    rng=np.random.default_rng(110320)
    t=np.arange(round(duration*RATE))/RATE
    stereo=np.zeros((len(t),2),dtype=np.float64)

    def add(start,sound,pan):
        idx=int(start*RATE)
        count=min(len(sound),len(t)-idx)
        if count>0:
            stereo[idx:idx+count,0]+=sound[:count]*np.cos((pan+1)*np.pi/4)
            stereo[idx:idx+count,1]+=sound[:count]*np.sin((pan+1)*np.pi/4)

    def keys(at,freq,vol=.19,length=3,pan=0):
        u=np.arange(round(length*RATE))/RATE
        envelope=(1-np.exp(-u/.007))*np.exp(-u/.74)
        partials=sum(amp*np.sin(np.pi*2*freq*mult*u)*np.exp(-u*loss) for mult,amp,loss in ((1,1,.04),(2,.31,.65),(4.014,.13,2.3),(6.82,.045,3)))
        add(at,vol*partials*envelope,pan)
        add(at+.137,vol*.17*partials*envelope,-pan)

    def pad(at,length,notes,vol):
        u=np.arange(round(length*RATE))/RATE
        shape=np.maximum(0,np.sin(np.pi*np.arange(len(u))/max(1,len(u)-1)))**1.8
        for i,f in enumerate(notes):
            osc=np.sin(2*np.pi*f*u+.08*np.sin(3.1*u))+ .20*np.sin(2*np.pi*(f*2+.12)*u)
            add(at,vol*shape*osc/len(notes),-.55+i*.45)

    def touch(at,dry):
        u=np.arange(int(.095*RATE))/RATE
        n=rng.normal(0,1,len(u))
        snap=(.52*np.sin(2*np.pi*(118+390*np.exp(-u/.008))*u)+.50*np.diff(n,prepend=0))*np.exp(-u/dry)
        add(at,snap*.105,-.13)
        add(at+.039,snap*.055,.23)

    if which=='brand':
        for at,n,notes in ((0,8,(110,164.81,246.94)),(6.3,9,(130.81,196,293.66)),(13,9,(98,146.83,220)),(20.4,10,(123.47,185,277.18)),(28.8,8.2,(110,164.81,246.94))):
            pad(at,n,notes,.135)
        for i,(at,f) in enumerate(((.6,329.63),(3.15,493.88),(4.48,392),(7.68,587.33),(9.12,293.66),(11.35,440),(14.04,246.94),(16.9,369.99),(20.13,277.18),(24.47,554.37),(29.46,329.63),(32.92,246.94),(33.14,369.99),(33.61,493.88))):
            keys(at,f,.20 if at in (11.35,24.47,33.61) else .13,3,(-.35,.3)[i%2])
        for at,dry in ((6.43,.011),(10.99,.008),(16.65,.009),(23.89,.005),(29.91,.003),(30.37,.004),(31.04,.003)):
            touch(at,dry)
    else:
        start,cue={'capture':(329.63,4.7),'at-hand':(246.94,2.75),'draft':(277.18,4)}[which]
        pad(0,duration,(start/3,start/2,start),.13)
        for i,(at,f) in enumerate(((.26,start),(cue-.41,start*1.5),(cue,start*2),(duration-2,start*1.5))):
            keys(at,f,.18,2.8,-.35+.23*i)
        touch(cue-.2,.007)
    fade=np.minimum(1,np.minimum(t/.18,(duration-t)/.72))
    stereo*=fade[:,None]
    assert np.isfinite(stereo).all()
    peak=np.max(np.abs(stereo))
    stereo=stereo*.71/max(peak,.005)
    with wave.open(str(path),'wb') as wav:
        wav.setnchannels(2);wav.setsampwidth(2);wav.setframerate(RATE)
        wav.writeframes((stereo*32767).astype('<i2').tobytes())
