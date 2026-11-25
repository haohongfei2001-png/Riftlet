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
 assert.match(map,/<lastmod>2026-11-25<\/lastmod>/);
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
 assert.equal(app.softwareVersion,'1.0.11');
 assert.match(app.description,/Chrome/);
 assert.match(app.description,/Edge/);
 assert.match(app.downloadUrl,/v1\.0\.11\/Riftlet-1\.0\.11\.dmg$/);
 assert.equal((html.match(/type="application\/ld\+json"/g)||[]).length,1);
});
test('installation dialog identifies the signed disk image in both languages', () => {
 const dialog = html.match(/<dialog\b[^>]*\bid="release-dialog"[^>]*>([\s\S]*?)<\/dialog>/);
 assert.ok(dialog);
 assert.match(dialog[1], /Disk image SHA-256/);
 assert.match(dialog[1], /磁盘映像 SHA-256|安装包 SHA-256/);
 const code = dialog[1].match(/<code>([\da-f]+(?:<wbr>[\da-f]+)*)<\/code>/);
 assert.ok(code);
 assert.equal(code[1].replaceAll('<wbr>', ''), '1611fbbd1866d1e686489dece6b8fbc03d7f0dcde4669a0b58c8a9a95c0c8f41');
 assert.ok(dialog[1].includes('href="https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.11"'));
});
test('IndexNow domain ownership file matches key exactly',()=>{
 assert.match(key,/^[a-z0-9]{8,128}$/);
 assert.equal(fs.readFileSync(path.join(root,key+'.txt'),'utf8'),key);
});
