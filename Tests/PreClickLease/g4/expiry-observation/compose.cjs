'use strict';

// Builds a static private QA script. No browser, request, URL or session input.
const fs = require('node:fs'), crypto = require('node:crypto');
const {declaredExpiry,expiryReceipt} = require('./expiry.cjs');
const baselines = new Set([
  '8f5add018ef46edcb232ef3340340924068c85ea5e7cccf97bf6a21a33693351',
  '26719be425230c8c32923f6b2f10a8613d99529bd5ff2fc17ef3e93dcacfe231'
]);
function compose(original) {
  if (!baselines.has(crypto.createHash('sha256').update(original).digest('hex'))) throw Error('Unrecognized passive observer');
  let result = original;
  function replace(from,to) {
    if (result.split(from).length!==2) throw Error('Passive reader structure changed');
    result=result.replace(from,()=>to);
  }
  replace('  function link(response, status) {', '  let knownExpiry = null;\n'+declaredExpiry.toString()+'\n'+expiryReceipt.toString()+'\n  function link(response, status) {');
  replace('    signed = dest.href; responseField = keys[0]; responseStatus = status;',
    '    knownExpiry = declaredExpiry(dest);\n    signed = dest.href; responseField = keys[0]; responseStatus = status;');
  replace('    final = Object.freeze(report(complete && restored ? "CALIBRATED" : "INCONCLUSIVE"));',
    '    const observed = report(complete && restored ? "CALIBRATED" : "INCONCLUSIVE");\n'+
    '    final = Object.freeze({...observed, declaredExpiry:expiryReceipt(knownExpiry, observed)});\n    knownExpiry = null;');
  return result;
}
if (require.main===module) {
  const [original,destination] = process.argv.slice(2);
  if (!original || !destination || process.argv.length!==4) throw Error('Usage: compose.cjs PINNED_PASSIVE.js NEW_OUTPUT.js');
  fs.writeFileSync(destination,compose(fs.readFileSync(original,'utf8')),{flag:'wx',mode:0o600});
}
module.exports={compose};
