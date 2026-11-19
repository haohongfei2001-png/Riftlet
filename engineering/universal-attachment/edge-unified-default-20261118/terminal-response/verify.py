#!/usr/bin/env python3
"""Offline only: hash-pinned original HAR -> same-file chain -> bounded response format/terminal.
No HTTP clients, browser commands, clipboard, upload, replay or admission writes.
All non-allowlisted HAR bodies remain opaque structural offsets. Never emits IDs/URLs/headers/body.
"""
import argparse,hashlib,json,math,mmap,os,re,runpy,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
SHA=re.compile(r'[a-f0-9]{64}\Z')
FILE=re.compile(r'file[-_][A-Za-z0-9_-]{6,128}\Z')
NAME=re.compile(r'riftlet-[A-F0-9]{8}(?:-[A-F0-9]{4}){3}-[A-F0-9]{12}\.png\Z')
EVENTS={'file.processing.started','file.processing.file_ready','file.processing.completed','file.processing.failed'}

def need(ok,code):
 if not ok:raise ValueError(code)
def sha(data):return hashlib.sha256(data).hexdigest()
def strict(pairs):
 out={}
 for k,v in pairs:need(k not in out,'duplicate_json_key');out[k]=v
 return out

def load_sources():
 pins=json.loads((HERE/'source-pins.json').read_text())
 # Existing committed parser provides structural offsets, not network access.
 parser=HERE.parent.parent/'edge-fresh-pair-20261117/verify_terminal.py'
 need(sha(parser.read_bytes())==pins['structuralParserSHA256'],'structural_parser_changed')
 source=runpy.run_path(str(parser))
 for name,digest in pins['upstreamFiles'].items():need(sha((HERE/'upstream'/name).read_bytes())==digest,'upstream_source_changed')
 return source['StructuralJSON'],source['payload']

def classify_entity(raw,file_digest):
 out={'entityBytes':len(raw),'entitySHA256':sha(raw),'format':'UNRECOGNIZED','terminal':'UNKNOWN','sameFileFrames':0,
      'completedFrameObserved':False,'completeKnownSequence':False,'sseDataLines':0,'records':[]}
 if not raw or len(raw)>16384 or not SHA.fullmatch(file_digest):return out
 try:
  text=raw.decode('utf-8','strict');lines=text.splitlines();nonempty=[x for x in lines if x.strip()]
  out['sseDataLines']=sum(x.startswith('data:') for x in lines)
  if nonempty and all(x.lstrip().startswith('{') for x in nonempty):
   out['format']='NDJSON';frames=nonempty
   need(raw.endswith((b'\n',b'\r')),'incomplete_record_delimiter')
  elif out['sseDataLines']:
   out['format']='SSE';frames=[];pending=[];event='';headers=[]
   # SSE dispatches data only at a blank line, not just at EOF.
   for line in re.findall(r'([^\r\n]*)(?:\r\n|\r|\n)',text):
    if not line:
     if pending:frames.append('\n'.join(pending));headers.append(event);pending=[]
     event=''
    elif line.startswith(':'):pass
    else:
     key,sep,value=line.partition(':');value=value[1:] if value.startswith(' ') else value
     if key=='data':pending.append(value)
     elif key=='event':event=value
   need(not pending and raw.endswith((b'\n',b'\r')),'incomplete_sse_frame')
  else:return out
  need(1<=len(frames)<=16,'bounded_frames')
  records=[]
  for index,line in enumerate(frames):
   need(len(line.encode())<=4096,'bounded_record')
   d=json.loads(line,object_pairs_hook=strict,parse_constant=lambda _:(_ for _ in ()).throw(ValueError('nonfinite_json')))
   need(type(d) is dict and type(d.get('file_id')) is str and FILE.fullmatch(d['file_id']) and sha(d['file_id'].encode())==file_digest,'file_id_not_exact')
   need(d.get('event') in EVENTS,'unrecognized_service_event')
   if out['format']=='SSE':need(headers[index] in ('','message',d['event']),'sse_event_payload_conflict')
   p=d.get('progress');need(type(p) in (int,float) and math.isfinite(p) and 0<=p<=100,'invalid_progress')
   records.append({'event':d['event'],'progressPercent':p,'sameFileID':True})
  kinds=[x['event'] for x in records];points=[x['progressPercent'] for x in records]
  need(len(set(kinds))==len(kinds),'duplicate_event')
  need(points==sorted(points),'regressive_progress')
  out.update(sameFileFrames=len(records),records=records,completedFrameObserved='file.processing.completed' in kinds)
  expected=['file.processing.started','file.processing.file_ready','file.processing.completed']
  if kinds==expected and points[-1]==100:out.update(terminal='FILE_PROCESSING_COMPLETED',completeKnownSequence=True)
  if kinds in (['file.processing.started','file.processing.failed'],['file.processing.started','file.processing.file_ready','file.processing.failed']):out.update(terminal='FILE_PROCESSING_FAILED',completeKnownSequence=True)
 except (ValueError,TypeError,KeyError,UnicodeError):
  # No partial favorable fragments survive an ambiguous/truncated/mixed entity.
  out.update(terminal='UNKNOWN',sameFileFrames=0,completedFrameObserved=False,completeKnownSequence=False,records=[],rejectedEntity=True)
 return out

def replay_upstream(raw):
 p=subprocess.run(['node','--no-warnings','--experimental-strip-types',str(HERE/'replay-upstream.mjs')],input=raw,capture_output=True,timeout=10)
 need(p.returncode==0,'upstream_replay_failed')
 d=json.loads(p.stdout);need(d['inputBytes']==len(raw) and d['inputSHA256']==sha(raw),'upstream_different_bytes')
 return d

def audit(har,case):
 Structural,payload=load_sources();need(har.is_file() and not har.is_symlink() and har.stat().st_size<=96*1024*1024,'bounded_original_har_required')
 with har.open('rb') as f,mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as b:
  need(sha(b)==case['harSHA256'],'original_har_hash_mismatch')
  j=Structural(b);need(not b[j.skip(0):].strip(),'whole_har_closed_required')
  log=j.fields((0,len(b)),'log')['log'];entries=j.fields(log,'entries')['entries']
  wanted={x[k] for x in case['files'] for k in ['createEntry','putEntry','processEntry']};selected={};count=0
  for i,(_,entry) in enumerate(j.items(entries)):
   count=i+1
   if i in wanted:selected[i]=entry
  need(count==case['entryCount'],'har_entry_count_changed')
  def fields(entry):return j.fields(selected[entry],'request','response','_resourceType')
  def text(span,limit=16384):
   need(span and span[1]-span[0]<=limit,'bounded_text_required');v=json.loads(b[slice(*span)],object_pairs_hook=strict);need(type(v) is str,'string_required');return v
  def obj_body(region):
   state,raw=payload(j,region,16384);need(raw and state in ('TEXT','BASE64'),'original_body_missing');return json.loads(raw,object_pairs_hook=strict)
  def request(row,method,route=None):
   r=j.fields(row['request'],'method','url','postData','headers');need(j.string_matches(r.get('method'),re.compile(method.encode())),'method_mismatch')
   if route:need(j.string_matches(r.get('url'),re.compile(re.escape(route.encode()))),'endpoint_mismatch')
   return r
  def response(row,status):
   r=j.fields(row['response'],'status','content','headers','_error');need(j.number(r.get('status'))==status,'status_mismatch');return r
  def header(region,key):
   if not region:return None
   matches=[]
   for _,x in j.items(region):
    d=j.fields(x,'name','value')
    if j.string_matches(d.get('name'),re.compile(key.encode(),re.I)):matches.append(text(d['value'],1024))
   need(len(matches)<=1,'duplicate_header');return matches[0] if matches else None
  results=[]
  for original in case['files']:
   c,p,u=[fields(original[k]) for k in ['createEntry','processEntry','putEntry']]
   cr=request(c,'POST','https://chatgpt.com/backend-api/files');pr=request(p,'POST','https://chatgpt.com/backend-api/files/process_upload_stream');ur=request(u,'PUT')
   cb=obj_body(cr.get('postData'));pb=obj_body(pr.get('postData'));cres=response(c,200);pres=response(p,200);ures=response(u,201);allocation=obj_body(cres['content'])
   name=cb.get('file_name');identifier=allocation.get('file_id');wire=cb.get('file_size');locator=allocation.get('upload_url')
   need(type(name) is str and NAME.fullmatch(name) and sha(name.encode())==original['filenameSHA256'],'original_operation_filename_mismatch')
   need(type(identifier) is str and FILE.fullmatch(identifier) and sha(identifier.encode())==original['fileIDSHA256'],'original_created_file_id_mismatch')
   need(pb.get('file_name')==name and pb.get('file_id')==identifier,'process_original_file_mismatch')
   need(type(locator) is str and re.fullmatch(r'https://[a-z0-9.-]+/[^#\s\x00-\x20]+',locator,re.I) and locator==text(ur['url']),'allocated_storage_locator_mismatch')
   need(type(wire) is int and wire>0 and header(ur.get('headers'),'content-length')==str(wire),'wire_length_mismatch')
   need(bool(header(ures.get('headers'),'etag')),'storage_etag_missing')
   need(original['createEntry']<original['putEntry']<original['processEntry'],'original_chain_order')
   content=j.fields(pres['content'],'mimeType','size');mime=text(content['mimeType'],128)
   need(mime=='text/event-stream','process_mime_changed')
   body_state,raw=payload(j,pres['content'],16384);size=j.number(content.get('size'))
   error=None
   for region in [pres, j.fields(p['response'],'_error')]:
    if region.get('_error') and b[slice(*region['_error'])] != b'null':
     value=text(region['_error'],200);error=value if re.fullmatch(r'net::ERR_[A-Z0-9_]+',value) else 'OTHER_BROWSER_ERROR'
   resource=text(p['_resourceType'],80) if p.get('_resourceType') else 'absent'
   if resource not in ('xhr','fetch','eventsource','other','absent'):resource='other'
   result={**original,'createAndProcessStatus':200,'putStatus':201,'putETagPresent':True,'originalFilenameCreatePUTProcessChainVerified':True,'mimeType':mime,'resourceType':resource,'declaredContentBytes':size,'bodyState':body_state,'browserError':error,'terminal':'UNKNOWN','productCompletionAdmitted':False}
   if raw is not None:
    d=classify_entity(raw,original['fileIDSHA256']);d['declaredLengthMatches']=len(raw)==size
    if not d['declaredLengthMatches']:d['terminal']='UNKNOWN'
    result.update(entity=d,terminal=d['terminal'],upstreamSSEReplay=replay_upstream(raw))
   else:result['format']='UNDETERMINED_NO_BODY'
   results.append(result)
  return {'schema':1,'scope':'Hash-pinned historical originals only; offline closed-field projection, no private endpoint call','harSHA256':case['harSHA256'],'harBytes':len(b),'entryCount':count,'files':results,'claims':'Service entity observation is separate from product START/completion and source admission. Missing bodies cannot borrow 606 framing or events.','browserOrServiceRequests':0,'GUIActions':0}

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--case',required=True,choices=['606','612-613','625']);p.add_argument('--har',type=Path,required=True);p.add_argument('--out',type=Path)
 a=p.parse_args();cases=json.loads((HERE/'cases.json').read_text());result=audit(a.har,cases[a.case]);data=(json.dumps(result,indent=2,sort_keys=True)+'\n').encode()
 if a.out:
  with a.out.open('xb') as f:f.write(data)
  print(json.dumps({'result':[r['terminal'] for r in result['files']],'bytes':len(data),'sha256':sha(data)}))
 else:sys.stdout.buffer.write(data)
if __name__=='__main__':
 os.umask(0o077)
 try:main()
 except (OSError,ValueError,KeyError,TypeError,IndexError,subprocess.SubprocessError):
  print('{"result":"REFUSED_ORIGINAL_BINDING_OR_ENTITY_UNAVAILABLE","terminal":"UNKNOWN"}');sys.exit(2)
