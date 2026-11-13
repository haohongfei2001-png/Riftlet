"""Write UTF-8 Simplified Chinese sidecars from the same editorial cue lists."""
from pathlib import Path
from film import ROOT,CAPTIONS

def clock(seconds):
    ms=round(seconds*1000)
    h,ms=divmod(ms,3600000);m,ms=divmod(ms,60000);sec,ms=divmod(ms,1000)
    return f'{h:02}:{m:02}:{sec:02},{ms:03}'

def write(name,cues):
    blocks=[f'{i}\n{clock(a)} --> {clock(b)}\n{text}' for i,(a,b,text) in enumerate(cues,1)]
    (ROOT/'captions'/(name+'.zh-CN.srt')).write_text('\n\n'.join(blocks)+'\n',encoding='utf8')

if __name__=='__main__':
    write('riftlet-commercial',CAPTIONS)
    from portrait import SHORT_CAPTIONS
    write('riftlet-vertical',SHORT_CAPTIONS)
