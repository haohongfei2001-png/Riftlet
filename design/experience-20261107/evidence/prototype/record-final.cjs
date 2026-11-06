const {chromium}=require('/tmp/riftlet-headless-tools-20261107/node_modules/playwright-core');const fs=require('fs');
(async()=>{
const dir='/tmp/riftlet-design-qa-frames-7d19037/motion';fs.mkdirSync(dir,{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--no-first-run','--disable-default-apps','--disable-background-networking']});
const page=await browser.newPage({viewport:{width:1440,height:1120},deviceScaleFactor:1});
await page.goto('file:///tmp/riftlet-design-qa-20261107-native/design/experience-20261107/prototype/index.html?view=desktop');await page.waitForTimeout(300);
const cdp=await page.context().newCDPSession(page),frames=[],events=[];
cdp.on('Page.screencastFrame',async f=>{frames.push({data:f.data,t:f.metadata.timestamp});await cdp.send('Page.screencastFrameAck',{sessionId:f.sessionId})});
await cdp.send('Page.startScreencast',{format:'jpeg',quality:75,maxWidth:1440,maxHeight:1120,everyNthFrame:1});
let t0=Date.now();async function event(label,fn,pause=800){events.push({timeMs:Date.now()-t0,label});console.log(label);await fn();await page.waitForTimeout(pause)}
await page.waitForTimeout(600);
await event('arrival',()=>page.evaluate(()=>RiftPrototype.addScreenshot()),1000);
await event('attach-start-swallow',()=>page.evaluate(()=>RiftPrototype.attach(4)),1100);
await event('two-concurrent',()=>page.evaluate(()=>Promise.all([RiftPrototype.attach(1),RiftPrototype.attach(2)])),1100);
await event('reset',()=>page.evaluate(()=>RiftPrototype.reset()),700);
await event('failure-restores',()=>page.evaluate(async()=>{RiftPrototype.setScenario('failure');await RiftPrototype.attach(1)}),1500);
await event('no-target-preserves',()=>page.evaluate(async()=>{RiftPrototype.setScenario('no-target');await RiftPrototype.attach(2)}),1200);
await event('reduced-motion',()=>page.evaluate(async()=>{RiftPrototype.setScenario('success');RiftPrototype.state.settings.reduceMotion=true;RiftPrototype.render();await RiftPrototype.attach(1)}),1000);
await cdp.send('Page.stopScreencast');
const start=frames[0].t;frames.forEach((f,i)=>{f.ms=(f.t-start)*1000;fs.writeFileSync(dir+'/frame-'+String(i).padStart(4,'0')+'.jpg',Buffer.from(f.data,'base64'))});
fs.writeFileSync(dir+'/manifest.json',JSON.stringify({commit:'7d19037611c1228a2397cf44ed47bddd8f390213',method:'CDP Page.startScreencast JPEG actual rendered prototype frames; timestamps retained; no native production app used',events,frames:frames.map((f,i)=>({file:'frame-'+String(i).padStart(4,'0')+'.jpg',ms:f.ms}))},null,2));
console.log('frames '+frames.length);
const enc=await browser.newPage({viewport:{width:1440,height:1120}});await enc.setContent('<canvas id="c" width="1440" height="1120"></canvas>');
const result=await enc.evaluate(async frames=>{
 const images=await Promise.all(frames.map(f=>new Promise((resolve,reject)=>{let im=new Image();im.onload=()=>resolve(im);im.onerror=reject;im.src='data:image/jpeg;base64,'+f.data})));
 const c=document.querySelector('canvas'),ctx=c.getContext('2d');ctx.drawImage(images[0],0,0,c.width,c.height);
 const stream=c.captureStream(30),parts=[],mime=MediaRecorder.isTypeSupported('video/webm;codecs=vp9')?'video/webm;codecs=vp9':'video/webm';const rec=new MediaRecorder(stream,{mimeType:mime,videoBitsPerSecond:1800000});
 const done=new Promise(resolve=>{rec.ondataavailable=e=>parts.push(e.data);rec.onstop=async()=>{const blob=new Blob(parts,{type:mime}),reader=new FileReader();reader.onload=()=>resolve(reader.result.split(',')[1]);reader.readAsDataURL(blob)}});
 rec.start();const start=performance.now();for(let i=0;i<frames.length;i++){const wait=frames[i].ms-(performance.now()-start);if(wait>0)await new Promise(r=>setTimeout(r,wait));ctx.drawImage(images[i],0,0,c.width,c.height)}await new Promise(r=>setTimeout(r,600));rec.stop();return await done;
},frames);
fs.writeFileSync(dir+'/riftlet-motion.webm',Buffer.from(result,'base64'));fs.writeFileSync(dir+'/riftlet-motion.webm.b64',result);console.log('video '+Buffer.from(result,'base64').length);await browser.close();console.log('DONE');
})().catch(e=>{console.error(e);process.exit(1)});
