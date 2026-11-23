'use strict';
const assert=require('node:assert/strict'), test=require('node:test');
const fs=require('node:fs'), os=require('node:os'), path=require('node:path');
const {execFileSync}=require('node:child_process');
const {compose}=require('./compose.cjs');

test('existing passive VM harness and a matching/ambiguous expiry run without a network service',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-expiry-fixture-'));
  try {
    const base=path.join(__dirname,'../network');
    fs.writeFileSync(path.join(dir,'calibrate.js'),compose(fs.readFileSync(path.join(base,'calibrate.js'),'utf8')));
    const harness=fs.readFileSync(path.join(base,'calibrate.test.mjs'),'utf8');
    const original='const signedURL = "https://media.example.test/blob?signature=PRIVATE-TEST-VALUE";';
    assert.equal(harness.split(original).length,2);
    const url='https://qa00.blob.core.windows.net/local/only?sr=b&sv=2023-11-03&se=2027-01-29T00%3A00%3A00Z&canary=PRIVATE-TEST-VALUE';
    const testCase=`
      test('expiry projection appears only on final correlated fetch create and XHR PUT',async()=>{
        const h=harness();h.attach();await h.sendFetch(createURL,h.createBody);await h.settled();
        assert(!('declaredExpiry' in h.sample()));
        h.sendXHR(signedURL,h.testFile);await h.settled();
        assert(!('declaredExpiry' in h.sample()));
        const r=h.finished();assert.equal(r.status,'CALIBRATED');
        assert.deepEqual(JSON.parse(JSON.stringify(r.declaredExpiry)),{
          schema:'azure-storage-blob-sas-se',expiresUTC:'2027-01-29T00:00:00Z',operationSHA256:digest(uuid),
          uploadURLSHA256:digest(signedURL),pngSHA256:digest(original)});
        assert(!JSON.stringify(r).includes('PRIVATE-TEST-VALUE'));assert.equal(h.calls.length,2);
      });
      test('two allocated expiry values do not qualify even on a normal intact transfer',async()=>{
        const u=signedURL+'&se=2027-01-29T00%3A01%3A00Z';
        const h=harness({response:{upload_url:u}});h.attach();await h.sendFetch(createURL,h.createBody);await h.settled();
        h.sendXHR(u,h.testFile);await h.settled();
        const r=h.finished();assert.equal(r.status,'CALIBRATED');assert.equal(r.declaredExpiry,null);
      });`;
    fs.writeFileSync(path.join(dir,'composed.test.mjs'),harness.replace(original,'const signedURL = '+JSON.stringify(url)+';')+testCase);
    const env={...process.env}; delete env.NODE_TEST_CONTEXT; delete env.NODE_TEST_WORKER_ID;
    const suite=execFileSync(process.execPath,['--test','--test-reporter=tap',path.join(dir,'composed.test.mjs')],{timeout:30000,env,encoding:'utf8'});
    assert.match(suite,/ok \d+ - expiry projection appears/);
    assert.match(suite,/ok \d+ - two allocated expiry values/);
    assert.match(suite,/# skipped 0/); assert.match(suite,/# fail 0/);
    console.log('Composed observer VM suite: '+suite.match(/# tests (\d+)/)[1]+' passed');
  } finally {fs.rmSync(dir,{recursive:true,force:true});}
});
