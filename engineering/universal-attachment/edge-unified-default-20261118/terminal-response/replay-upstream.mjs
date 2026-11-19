// Offline only. Exact upstream TypeScript with Node type stripping; stdin never leaves this process.
import {ServerSentEventsParser} from './upstream/ServerSentEventsProtocol.ts';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const bytes=readFileSync(0);
if(bytes.length>16384)throw Error('bounded-entity-required');
const text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
const run=parts=>{let count=0;const p=new ServerSentEventsParser(()=>count++);for(const part of parts)p.addTextChunk(part);return count};
// Do not rewrite or add framing to the real entity. Different chunks use the same exact bytes.
const counts=[run([text]),run(Array.from(text)),run([text.slice(0,17),text.slice(17)])];
const control=[];const parser=new ServerSentEventsParser((event,data)=>control.push([event,data]));
parser.addTextChunk('event: diagnostic-control\ndata: neutral fixture\n\n');
if(control.length!==1||control[0][0]!=='diagnostic-control'||control[0][1]!=='neutral fixture')throw Error('upstream-control-failed');
process.stdout.write(JSON.stringify({inputBytes:bytes.length,inputSHA256:createHash('sha256').update(bytes).digest('hex'),sseEventsByChunkPartition:counts,neutralSSEPositiveControl:control.length,installedEdgeRuntimeTest:false})+'\n');
