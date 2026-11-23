'use strict';
const test=require('node:test'), assert=require('node:assert/strict');
const {declaredExpiry,expiryReceipt}=require('./expiry.cjs');
const {compose}=require('./compose.cjs');
const iso='2027-03-31T16:17:18.1234567Z';
const params={sr:['b'],sv:['2023-11-03'],se:[iso]};
function candidate(values=params,hostname='qa00.blob.core.windows.net') {
  const allowed = new Set(['sr','sv','se']);
  const possibleConflicts=new Set(['Expires','expires','expires_at','X-Amz-Expires','X-Goog-Expires']);
  return new Proxy({protocol:'https:',port:'',hostname,searchParams:{
    getAll(k){assert(allowed.has(k));return values[k]||[];},
    has(k){assert(possibleConflicts.has(k));return k in values;}
  }},{get(obj,name){assert(Object.hasOwn(obj,name),'Unnecessary URL field access');return obj[name];}});
}
test('UTC expiry survives with full precision; only explicit non-secret fields can be read',()=>{
  assert.deepEqual(declaredExpiry(candidate()),{schema:'azure-storage-blob-sas-se',expiresUTC:iso});
});
test('unknown provider, conflicting schemas, duplicate or imprecise/invalid expiry produce no time',()=>{
  for(const host of ['blob.core.windows.net','qa00.blob.core.windows.net.example','upload.example.test'])
    assert.equal(declaredExpiry(candidate(params,host)),null);
  const invalid=[{se:[]},{se:[iso,iso]},{sr:['c']},{sv:['2024-02-31']},{sv:[]},{Expires:['100']},{'X-Amz-Expires':['60']}];
  for(const value of ['2027-02-30T12:00:00Z','2027-01-01T00:00:60Z','2027-01-01T24:00:00Z','2027-05-05','2027-05-05T00:00:00+01:00','900','private-data'])
    invalid.push({se:[value]});
  for(const edit of invalid)assert.equal(declaredExpiry(candidate({...params,...edit})),null);
});
const h='1'.repeat(64);
const good={status:'CALIBRATED',restored:true,reason:null,inputs:1,changes:1,creates:1,responses:1,byteRequests:1,pending:0,
  observerPending:0,requestPending:false,cancelledByObserver:0,byteReturned:true,byteCompleted:true,sourceVerified:true,
  bytesVerified:true,sameFile:true,operationHash:h,create:{transport:'fetch',method:'POST',path:'/backend-api/files',responseStatus:200,
  fileNameField:'file_name',uploadURLField:'upload_url'},bytes:{transport:'xhr',method:'PUT',bodyType:'File',bodyScope:'entire-body',bodySize:12,
  pngBytes:12,responseStatus:201,urlSHA256:h,pngSHA256:h}};
test('receipt requires the positively correlated unique original File and a finished normal transfer',()=>{
  const t=declaredExpiry(candidate()), result=expiryReceipt(t,good);
  assert.deepEqual(Object.keys(result).sort(),['schema','expiresUTC','operationSHA256','uploadURLSHA256','pngSHA256'].sort());
  assert.equal(result.expiresUTC,iso); assert.equal(expiryReceipt(null,good),null);
  for(const [key,val] of [['status','OBSERVING'],['reason','read-error'],['inputs',2],['creates',2],['changes',0],['responses',0],
    ['byteRequests',2],['restored',false],['sameFile',false],['sourceVerified',false],['bytesVerified',false],
    ['pending',1],['requestPending',true],['cancelledByObserver',1],['operationHash','bad']])
    assert.equal(expiryReceipt(t,{...good,[key]:val}),null,key);
  for(const [key,val] of [['urlSHA256','missing'],['pngBytes',13],['bodyScope','partial'],['responseStatus',403],['bodyType','Blob']])
    assert.equal(expiryReceipt(t,{...good,bytes:{...good.bytes,[key]:val}}),null,key);
});
test('different base bytes cannot acquire this projection',()=>assert.throws(()=>compose('')));
