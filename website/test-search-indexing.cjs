'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const key='bf099d245e4947c8908a2d8f6d5e5994';
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const map=fs.readFileSync(path.join(root,'sitemap.xml'),'utf8');
const robots=fs.readFileSync(path.join(root,'robots.txt'),'utf8');
test('sitemap is public, canonical and recently updated',()=>{
 assert.match(map,/<loc>https:\/\/riftlet\.com\/<\/loc>/);
 assert.match(map,/<lastmod>2026-11-14<\/lastmod>/);
 assert.match(robots,/User-agent: \*/);
 assert.match(robots,/Sitemap: https:\/\/riftlet\.com\/sitemap\.xml/);
 assert.match(html,/<link rel="canonical" href="https:\/\/riftlet\.com\/"/);
});
test('Riftlet identity is explicit and there is no false capability claim',()=>{
 assert.match(html,/<title>Riftlet — Mac 截图一键附加到 ChatGPT \| 官方网站<\/title>/);
 const data=/<script type="application\/ld\+json">([^<]+)<\/script>/.exec(html);
 assert.ok(data,'exactly one JSON-LD SoftwareApplication');
 const app=JSON.parse(data[1]);
 assert.equal(app.name,'Riftlet');
 assert.equal(app.url,'https://riftlet.com/');
 assert.equal(app.softwareVersion,'1.0.1');
 assert.match(app.description,/Chrome/);
 assert.match(app.downloadUrl,/v1\.0\.1\/Riftlet-1\.0\.1\.dmg$/);
 assert.equal((html.match(/type="application\/ld\+json"/g)||[]).length,1);
});
test('IndexNow domain ownership file matches key exactly',()=>{
 assert.match(key,/^[a-z0-9]{8,128}$/);
 assert.equal(fs.readFileSync(path.join(root,key+'.txt'),'utf8'),key);
});
