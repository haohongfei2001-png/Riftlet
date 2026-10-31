#!/usr/bin/env python3
"""Bounded R2 synthetic AppKit captures on an isolated macOS CI desktop only.
Reuses the existing helper and original-pixel verifier; never launches Chrome.
"""
import argparse, hashlib, importlib.util, json, os, pathlib, subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('native',root/'scripts/capture-native-visual-evidence.py');base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
source=base.git(root,'rev-parse',os.environ.get('RIFTLET_BUILD_HEAD_SHA','HEAD')+'^{commit}');checkout=base.git(root,'rev-parse','HEAD')
if base.git(root,'status','--porcelain','--untracked-files=no'):raise SystemExit('clean source required')
if a.output.exists() or a.output.is_symlink():raise SystemExit('new output required')
a.output.mkdir(parents=True)
cases=[]
for side in ['left','right']:
 for v in ['Top','Middle','Bottom']:
  cases.append((side+v,['--r2-placement',side+v,'--visual-scene','12','--visual-entry','--r2-capacity','3']))
for n,h,i in [(1,'0','0'),(1,'0.9','0'),(10,'0.75','256'),(10,'0.25','6')]:
 cases.append((f'capacity{n}-hidden{h}-inset{i}',['--visual-scene','12','--r2-capacity',str(n),'--r2-occlusion',h,'--r2-inset',i,'--visual-entry-expanded']))
cases.append(('middle-page',['--visual-scene','12','--r2-capacity','3','--r2-page','1']))
cases.append(('last-page',['--visual-scene','12','--r2-capacity','3','--visual-last-page']))
report={'source':source,'checkout':checkout,'helperSHA256':hashlib.sha256(a.helper.read_bytes()).hexdigest(),'scope':'synthetic AppKit original-pixel captures, not production/physical acceptance','cases':[]}
for name,flags in cases:
 out=a.output/name
 cmd=[str(a.helper.resolve()),'--visual-clean','--export-native-evidence',str(out),'--evidence-source',source,'--evidence-checkout',checkout,*flags]
 row={'name':name,'status':'FAIL'}
 try:
  r=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=12)
  (a.output/(name+'.log')).write_bytes(r.stdout)
  capture=json.loads((out/'capture.json').read_text());base.verify_capture(out,capture,source,checkout)
  if r.returncode:raise ValueError('helperExitFailure')
  row['status']=capture['status']
 except (OSError,ValueError,subprocess.TimeoutExpired) as e:row['reason']=type(e).__name__+':'+str(e)
 report['cases'].append(row)
(a.output/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(0 if all(c['status']=='CAPTURED_NATIVE_WINDOWSERVER' for c in report['cases']) else 1)
