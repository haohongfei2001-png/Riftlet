'use strict';
// Assemble an authored local page with the checkout's shipping page program, byte for byte.
// The only fixture substitution is its address argument. Neither the app nor browser is reconfigured.
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');

function build(directory) {
  const source = fs.readFileSync(path.join(__dirname,'../../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'),'utf8');
  const sha = createHash('sha256').update(source).digest('hex');
  const prelude = "'use strict';\n(()=>{\n" +
    "if (!(location.protocol==='file:' || (location.protocol==='http:' && location.hostname==='127.0.0.1')) || top!==self) return;\n" +
    "const controlledAddress = {get href(){return document.querySelector('form')?.dataset.draftId==='original'?'https://chatgpt.com/?temporary-chat=true':'https://chatgpt.com/c/11111111-1111-4111-8111-111111111111';}};\n" +
    "const program=(function(location){\nreturn (";
  const suffix = "\n);})(controlledAddress);\nObject.defineProperty(window,'ownedProductPage',{value:Object.freeze({program,sha:"+JSON.stringify(sha)+"})});\n})();\n";
  fs.mkdirSync(directory,{recursive:true,mode:0o700});
  for (const name of ['index.html','fixture.js']) fs.copyFileSync(path.join(__dirname,name),path.join(directory,name),fs.constants.COPYFILE_EXCL);
  fs.writeFileSync(path.join(directory,'shipping-adapter.js'),prelude+source+suffix,{flag:'wx',mode:0o600});
  return sha;
}
module.exports={build};
if(require.main===module) {
  if(process.argv.length!==3) throw Error('One new fixture output directory required');
  console.log(build(path.resolve(process.argv[2])));
}
