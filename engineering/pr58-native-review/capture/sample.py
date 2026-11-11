from pathlib import Path
from PIL import Image,ImageStat
import argparse,hashlib,json,os,subprocess,select
parser=argparse.ArgumentParser(description="Photograph only windows owned by the isolated Riftlet review application.")
parser.add_argument("exe",type=Path)
parser.add_argument("snap",type=Path)
parser.add_argument("destination",type=Path)
opts=parser.parse_args();exe=opts.exe.resolve();dest=opts.destination.resolve()
assert exe.name=="Review" and exe.parent.name=="MacOS" and exe.parent.parent.parent.name=="Riftlet 界面预览.app"
dest.mkdir()
profile=dest/'home';profile.mkdir()
proc=subprocess.Popen([str(exe),'--window-receipts'],env=dict(os.environ,CFFIXED_USER_HOME=str(profile)),stdout=subprocess.PIPE,stdin=subprocess.PIPE,stderr=(dest/'app.log').open('w'),text=True,bufsize=1)
def read():
 if not select.select([proc.stdout],[],[],20)[0]:raise RuntimeError('window receipt timeout')
 line=proc.stdout.readline()
 if not line:raise RuntimeError('preview exited',proc.poll())
 return json.loads(line)
try:
 index=read();out=[]
 scenes=['settings-'+str(i) for i in range(len(index['settings']))]+['save-error']+index['surfaces']
 for style in ['light','dark']:
  for scene in scenes:
   proc.stdin.write(style+' '+scene+'\n');proc.stdin.flush();r=read()
   assert r['pid']==proc.pid and r['window']>0 and r['visible'],r
   if scene.startswith('history-'): assert r['width']==808 and 460<=r['height']<=500,('unexpected history initial frame',r)
   if scene.startswith('settings-'): assert 716<=r['width']<=814 and r['height']==580,('unexpected settings initial frame',r)
   target=dest/(style+'-'+scene+'.png')
   subprocess.run([str(opts.snap.resolve()),str(r['window']),str(proc.pid),str(target)],check=True,timeout=8)
   im=Image.open(target)
   assert im.width >= r['width']*.97 and im.height >= r['height']*.97 and abs((im.width/im.height)/(r['width']/r['height'])-1)<.08,('WindowServer presented a scaled/offstage window',r,im.size)
   assert min(im.size)>70 and max(ImageStat.Stat(im.convert('RGB')).stddev)>10,(scene,im.size)
   r.update(style=style,pixels=im.size,sha256=hashlib.sha256(target.read_bytes()).hexdigest(),file=target.name)
   out.append(r)
   (dest/'receipts.json').write_text(json.dumps({'settings':index['settings'],'scenes':index['surfaces'],'windows':out},ensure_ascii=False,indent=2))
finally:
 if proc.poll() is None:
  proc.stdin.write('quit\n');proc.stdin.flush()
  try:proc.wait(timeout=6)
  except subprocess.TimeoutExpired:proc.terminate();proc.wait(timeout=5)
