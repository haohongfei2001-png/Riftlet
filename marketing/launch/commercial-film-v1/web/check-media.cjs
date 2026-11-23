const { chromium } = require('playwright');
const fs = require('node:fs/promises');
const { join, dirname, relative, basename } = require('node:path');
const { pathToFileURL, fileURLToPath } = require('node:url');
const { createHash } = require('node:crypto');
const root = process.argv[2], output = process.argv[3];
const campaign = dirname(root);
const rel = url => relative(campaign, fileURLToPath(url));
const sha256 = async url => createHash('sha256').update(await fs.readFile(fileURLToPath(url))).digest('hex');
async function verify(browser,lang,entry) {
  const page = await browser.newPage();
  const sourceURL = pathToFileURL(join(root,entry)).href;
  await page.goto(sourceURL);
  const links = await page.evaluate(() => ({
    lang: document.documentElement.lang,
    movie:document.querySelector('.watch').href,
    cover:new URL(document.querySelector('meta[property="og:image"]').content,document.baseURI).href,
    twitter:new URL(document.querySelector('meta[name="twitter:image"]').content,document.baseURI).href,
    h264:document.createElement('video').canPlayType('video/mp4; codecs="avc1.64002A"'),
    aac:document.createElement('audio').canPlayType('audio/mp4; codecs="mp4a.40.2"')
  }));
  const result = {lang,entry:'web/'+entry};
  const image = await page.evaluate(async source => {
    const img = new Image(); img.src=source; await img.decode();
    return {width:img.naturalWidth,height:img.naturalHeight};
  },links.cover);
  result.share = {path:rel(links.cover),sha256:await sha256(links.cover),...image,sameTwitter:links.cover === links.twitter};
  const movie = {expected:'film/'+lang+'/master.mp4',link:rel(links.movie),sha256:await sha256(links.movie),h264:links.h264,aac:links.aac};
  result.movie = movie;
  let download = null;
  page.on('download', entry => { download = entry.suggestedFilename(); });
  await page.locator('.watch').click();
  try {await page.waitForURL(links.movie,{timeout:5000});} catch {}
  movie.navigation = rel(page.url());
  movie.download = download;
  movie.source = await page.locator('video').count() ? 'native media document' : null;
  if (movie.source) {
    await page.waitForFunction(() => {const v=document.querySelector('video');return !!(v?.readyState>=1 || v?.error);},{},{timeout:10000}).catch(()=>{});
    const details = await page.evaluate(async()=>{
      const v=document.querySelector('video');
      const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
      v.muted=true;
      let playError=null;
      try {await Promise.race([v.play(), delay(4500).then(()=>{if(v.paused)throw new Error('play timeout')})]);}
      catch (e) {playError=String(e);}
      let t=Date.now();
      while (v.currentTime<.4 && Date.now()-t<4500 && !v.error) await delay(60);
      const frames = v.getVideoPlaybackQuality?.();
      const info={duration:v.duration,width:v.videoWidth,height:v.videoHeight,currentTime:v.currentTime,decodedFrames:frames?.totalVideoFrames??null,droppedFrames:frames?.droppedVideoFrames??null,readyState:v.readyState,mediaError:v.error?.message??null,playError};
      v.pause();
      return info;
    });
    Object.assign(movie,details);
  }
  result.passed=links.lang===lang && result.share.path==='social/share/'+lang+'.jpg' && result.share.width===1200 && result.share.height===630 && result.share.sameTwitter && movie.link===movie.expected && movie.navigation===movie.expected && Math.abs(movie.duration-20)<.02 && movie.width===1920 && movie.height===1080 && movie.currentTime>0 && movie.decodedFrames>0;
  await page.close();
  return result;
}
(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_BIN || undefined});
  const report={checkedUTC:new Date().toISOString(),browser:'Playwright Chromium headless shell '+browser.version(),method:'Opened each integrated HTML using file://; followed its visible Watch link in a fresh browser page; decoded OG image and sampled native video playback.',script:basename(__filename),command:'NODE_PATH=<path-to-playwright-node_modules> CHROMIUM_BIN=<path-to-chromium-headless-shell> node riftlet-web-integrated.cjs <campaign/web> <output.json>'};
  try{report.results=await Promise.all([verify(browser,'zh-CN','index.html'),verify(browser,'en','en.html')]);}
  finally{await browser.close();}
  report.passed=report.results.every(r=>r.passed);
  await fs.writeFile(output,JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report));
  if(!report.passed)process.exitCode=1;
})().catch(err=>{console.error(err);process.exitCode=1;});
