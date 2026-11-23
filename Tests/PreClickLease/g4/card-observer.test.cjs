'use strict';
const assert = require('node:assert/strict');
const {test} = require('node:test');
const {spawn} = require('node:child_process');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const {pathToFileURL} = require('node:url');
const {FixtureDriver} = require('../../OriginalDocumentDelivery/renderer/driver.cjs');
const {cleanupOwnedChrome} = require('../../WebPageProgram/native-chrome-cleanup.cjs');

test('Original G4 card in an isolated, offline DOM', async t => {
    const binary = process.env.RIFTLET_G4_BROWSER || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
    const profile = fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-g4-observer-'));
    const fixture = path.join(profile,'test.html');
    fs.writeFileSync(fixture, '<!doctype html><main></main>');
    const child = spawn(binary,['--headless=new','--remote-debugging-pipe','--user-data-dir='+profile,'--no-first-run',
        '--no-default-browser-check','--disable-extensions','--disable-sync','--disable-background-networking',
        '--disable-component-update','--host-resolver-rules=MAP * ~NOTFOUND','--proxy-server=http://127.0.0.1:1','about:blank'],
        {detached:true, stdio:['ignore','ignore','ignore','pipe','pipe']});
    const exited = new Promise(resolve => child.once('exit',resolve)), driver = new FixtureDriver(child);
    try {
        const uri = pathToFileURL(fixture).href, tab = await driver.open(uri);
        await driver.call('Target.activateTarget',{targetId:tab.targetId});
        const source = fs.readFileSync(path.join(__dirname,'card-observer.js'),'utf8');
        // A local file supplies the DOM. Only the URL and navigation identity are fixture inputs.
        const expression = '('+runCases.toString()+')('+JSON.stringify(source)+','+JSON.stringify(uri)+')';
        const res = await driver.call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true},tab.sessionId);
        if (res.exceptionDetails) throw Error(res.exceptionDetails.exception?.description || res.exceptionDetails.text);
        for (const row of res.result.value) await t.test(row.name,()=>assert.equal(row.observed,row.expected));
    } finally {
        await cleanupOwnedChrome(child,exited);
        fs.rmSync(profile,{recursive:true});
    }
});

async function runCases(source,fixtureURL) {
    if (document.readyState!=='complete') await new Promise(ok=>addEventListener('load',ok,{once:true}));
    if (location.href!==fixtureURL || document.visibilityState!=='visible') throw Error('Local visible fixture required');
    const caseNames = ['span shell', 'converted div', 'figure', 'named shell', 'dialog popup', 'hidden other editor',
        'hidden original editor','replaced editor','second visible editor','nested foreign layout','foreign form',
        'swapped document entry','changed URL','baseline error','baseline error rebuilt','baseline unnamed shell reused',
        'baseline preview rebuilt','baseline alert reused','PNG sibling preview','WEBP sibling preview',
        'PNG sibling progress','WEBP sibling progress','text-only competing progress','other operation in shell',
        'nested competing card','duplicate alert','visible progress','missing remove','generic alert','hidden alert',
        'upload waiting','unrelated previous attachment','baseline ambiguous composer','modern without form','modern foreign owner'];
    const positives = new Set(['span shell','converted div','figure','named shell','dialog popup',
                               'hidden other editor','unrelated previous attachment','modern without form']);
    const rows = [];
    const id = 'bb7be9ff-154f-47bc-81e5-c73ce7963a40', other='00112233-4455-4677-8899-aabbccddeeff';
    const png='riftlet-'+id+'.png', webp='riftlet-'+id+'.webp';
    const url='https://chatgpt.com/?temporary-chat=true';
    for (const name of caseNames) {
        const main=document.querySelector('main');
        main.innerHTML='<form><div data-composer-layout><div contenteditable="true">draft</div><div class="row"></div></div></form>';
        if (name.startsWith('modern ')) main.innerHTML='<div data-composer-placement><div contenteditable="true" id="prompt-textarea">draft</div><div class="row"></div></div>';
        const original=main.querySelector('[contenteditable]'), row=main.querySelector('.row');
        const alternateEditor=()=>main.insertAdjacentHTML('beforeend','<form><div data-composer-layout><textarea>x</textarea></div></form>');
        const make=(tag,attr={})=>{const n=document.createElement(tag); for(const [k,v] of Object.entries(attr))n.setAttribute(k,v);return n;};
        const shell=make('span',{'class':'group/composer-attachment'}), alert=make('span',{role:'alert','aria-label':png});
        const remove=make('button',{type:'button','aria-label':'Remove '+png}); remove.innerText='×';alert.innerText='Upload failed';
        const error=()=>{shell.append(alert, remove);row.append(shell)};
        const preview=(file)=>{const n=make('div',{class:'composer-attachment-surface group/composer-attachment'});
            n.append(make('img',{alt:file}));row.append(n);return n;};
        if (name==='baseline error' || name==='baseline error rebuilt') error();
        if (name==='baseline preview rebuilt') preview(webp);
        if (name==='baseline unnamed shell reused') row.append(shell);
        if (name==='baseline alert reused') row.append(alert);
        if (name==='unrelated previous attachment') preview('riftlet-'+other+'.png');
        if (name==='baseline ambiguous composer') alternateEditor();
        const fakeLocation={href:url}, fakeWindow={navigation:{currentEntry:{id:'one'}}};
        const bind=Function('window','location',source+';return observeNamedUploadError;')(fakeWindow,fakeLocation);
        let observe;
        try { observe=bind(original); } catch (e) {
            if(name!=='baseline ambiguous composer'||e.message!=='G4_DRAFT_NOT_BOUND') throw e;
            rows.push({name,observed:false,expected:false});continue;
        }
        if (name==='baseline error rebuilt' || name==='baseline preview rebuilt') row.replaceChildren();
        if (name==='baseline error rebuilt') row.insertAdjacentHTML('beforeend',shell.outerHTML);
        else error();
        if (name==='converted div' || name==='figure' || name==='dialog popup' || name==='named shell') {
            const tag=name==='figure'?'figure':'div';
            const attrs=name==='figure'?{'data-composer-image-attachment':''}:name==='named shell'?{'data-file-name':png}:
                name==='dialog popup'?{role:'button','aria-haspopup':'dialog'}:{class:'composer-attachment-surface group/composer-attachment'};
            const variant=make(tag,attrs);
            if(name==='converted div'){alert.setAttribute('aria-label',webp);remove.setAttribute('aria-label','Remove '+webp);}
            variant.append(alert,remove);shell.replaceWith(variant);
        }
        if (name==='hidden other editor' || name==='second visible editor') {
            alternateEditor();if(name==='hidden other editor')main.lastElementChild.hidden=true;
        }
        if (name==='hidden original editor') original.hidden=true;
        if (name==='replaced editor') original.replaceWith(original.cloneNode(true));
        if (name==='nested foreign layout' || name==='foreign form') {
            const foreign=make(name==='foreign form'?'form':'div',{'data-composer-layout':''});
            row.append(foreign);foreign.append(shell);
        }
        if (name==='modern foreign owner') {const otherOwner=make('div',{'data-chatgpt-composer':''});row.append(otherOwner);otherOwner.append(shell);}
        if (name==='swapped document entry')fakeWindow.navigation.currentEntry.id='two';
        if (name==='changed URL')fakeLocation.href='https://example.invalid/';
        if (name.endsWith('sibling preview'))preview(name.startsWith('PNG')?png:webp);
        if (name.endsWith('sibling progress') || name==='text-only competing progress') {
            const meter=make('span',{role:'progressbar'});
            if(name.startsWith('text-only'))meter.innerText='Uploading '+webp;
            else meter.setAttribute('aria-label','Uploading '+(name.startsWith('PNG')?png:webp));
            row.append(meter);
        }
        if (name==='other operation in shell')shell.append(make('img',{alt:'riftlet-'+other+'.png'}));
        if (name==='nested competing card')shell.append(preview(webp));
        if (name==='duplicate alert')shell.append(alert.cloneNode(true));
        if (name==='visible progress')shell.append(make('progress'));
        if (name==='missing remove')remove.remove();
        if (name==='generic alert')alert.removeAttribute('aria-label');
        if (name==='hidden alert')alert.hidden=true;
        if (name==='upload waiting')alert.innerText='Uploading';
        rows.push({name,expected:positives.has(name),observed:observe(id).uniqueNamedCard});
    }
    return rows;
}
