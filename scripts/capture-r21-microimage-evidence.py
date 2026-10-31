#!/usr/bin/env python3
"""R2.1 exact synthetic fixtures on the isolated CI WindowServer, no Chrome."""
import argparse, hashlib, importlib.util, json, os, pathlib, subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('native',root/'scripts/capture-native-visual-evidence.py');base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
source=base.git(root,'rev-parse',os.environ.get('RIFTLET_BUILD_HEAD_SHA','HEAD')+'^{commit}');checkout=base.git(root,'rev-parse','HEAD')
if base.git(root,'status','--porcelain','--untracked-files=no'):raise SystemExit('clean source required')
fixtures=root/'Tests/NativeVisualEvidence/R21Fixtures'
for row in json.loads((fixtures/'manifest.json').read_text()):
 if hashlib.sha256((fixtures/row['file']).read_bytes()).hexdigest()!=row['sha256']:raise SystemExit('fixture hash mismatch')
if a.output.exists() or a.output.is_symlink():raise SystemExit('new output required')
a.output.mkdir(parents=True)
cases=[]
for side in ['left','right']:
 for hidden in ['0','0.25','0.9']:
  cases.append((f'{side}-{hidden}', ['--r2-placement',side+'Middle','--r2-occlusion',hidden,'--appearance','light' if side=='left' else 'dark']))
cases += [('preview', ['--visual-preview-index','1']),('strict-start',['--visual-timeline'])]
report={'source':source,'checkout':checkout,'scope':'actual WindowServer synthetic fixture pixels; not physical input or real upload','cases':[]}
for name,flags in cases:
 out=a.output/name
 cmd=[str(a.helper.resolve()),'--visual-clean','--r21-fixtures',str(fixtures),'--visual-scene','12','--r2-capacity','6','--export-native-evidence',str(out),'--evidence-source',source,'--evidence-checkout',checkout,*flags]
 row={'name':name,'status':'FAIL'}
 try:
  r=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=20)
  (a.output/(name+'.log')).write_bytes(r.stdout)
  capture=json.loads((out/'capture.json').read_text());base.verify_capture(out,capture,source,checkout)
  if r.returncode:raise ValueError('helper exit failure')
  row['status']=capture['status']
 except (OSError,ValueError,subprocess.TimeoutExpired) as e:row['reason']=type(e).__name__+':'+str(e)
 report['cases'].append(row)
(a.output/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(0 if all(c['status']=='CAPTURED_NATIVE_WINDOWSERVER' for c in report['cases']) else 1)
