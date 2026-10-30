/* Riftlet / Passage — original vector construction, 2026-10-30.
 * Run: NODE_PATH="$CODEX_PRIMARY_RUNTIME_NODE_MODULES" node tools/build-brand.cjs
 * Raster exports use sharp. No remote fonts, images or runtime dependencies in SVGs.
 */
'use strict';
const fs=require('node:fs');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const sharp=require('sharp');
const root=path.resolve(__dirname,'..');
const out=path.join(root,'brand');
const assets=path.join(root,'site','assets');
fs.mkdirSync(out,{recursive:true}); fs.mkdirSync(assets,{recursive:true});
const C={ink:'#123E38',mint:'#46D1B1',paper:'#F4F1E8',warm:'#D7A482'};
// A gently sloping content plane and a stable vertical edge. Two editable paths.
const plane='M 58 65 L 143 48 C 160 44 177 56 178 74 C 179 91 169 107 167 127 C 165 146 170 164 175 181 C 181 199 172 208 155 205 L 59 197 C 44 195 36 184 36 170 L 36 93 C 36 79 43 69 58 65 Z';
const edge='M 207 42 Q 215 42 215 50 L 215 206 Q 215 214 207 214 C 200 209 196 199 196 186 L 196 70 C 196 57 200 47 207 42 Z';
// Optical version: larger opening, calmer curve and stronger edge for 16/32 pixels.
const smallPlane='M 57 65 L 139 48 C 157 44 173 56 174 75 C 175 92 166 108 164 127 C 162 146 167 164 172 181 C 177 198 168 207 152 205 L 58 197 C 43 195 35 184 35 170 L 35 93 C 35 79 42 69 57 65 Z';
const smallEdge='M 207 40 Q 216 40 216 49 L 216 207 Q 216 216 207 216 Q 193 208 193 188 L 193 68 Q 193 48 207 40 Z';
const paths=(fill=C.ink,small=false)=>`<path id="content-plane" fill="${fill}" d="${small?smallPlane:plane}"/><path id="screen-edge" fill="${fill}" d="${small?smallEdge:edge}"/>`;
const svg=(body,w=256,h=256,label='Riftlet — Passage')=>`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-labelledby="title"><title id="title">${label}</title>${body}</svg>\n`;
const mark=(fill=C.ink,small=false)=>svg(paths(fill,small));
const aPaths=(fill=C.ink)=>`<g fill="${fill}"><path d="M 43 65 L 91 44 L 91 214 L 43 192 Q 29 186 29 171 L 29 88 Q 29 72 43 65 Z"/><path d="M 103 44 L 152 44 C 195 44 219 66 219 105 C 219 132 203 152 178 160 L 227 214 L 169 214 L 121 153 C 113 142 115 132 127 126 C 150 115 163 113 163 97 C 163 83 154 79 136 75 C 111 70 103 62 103 44 Z"/></g>`;
const cPaths=(fill='#332A3C')=>`<g fill="${fill}"><path d="M 24 88 L 93 52 Q 105 46 120 49 L 208 68 Q 216 70 220 77 L 150 111 Q 138 117 123 114 L 26 99 Q 15 97 24 88 Z"/><path d="M 222 81 Q 233 91 233 109 L 233 212 Q 233 229 219 224 L 176 201 Q 161 192 161 176 L 161 134 Q 161 121 171 114 L 181 108 L 181 173 Q 181 182 187 178 Q 192 174 192 165 L 192 103 Z"/></g>`;
function appIcon(size=1024){
 const small=size<=32;
 return svg(`<defs><linearGradient id="tile" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#71E2C8"/><stop offset="0.46" stop-color="${C.mint}"/><stop offset="1" stop-color="#23B598"/></linearGradient><linearGradient id="rim" x1="0" y1="0" x2="0.8" y2="1"><stop stop-color="#E7FFF8" stop-opacity=".65"/><stop offset=".55" stop-color="#E7FFF8" stop-opacity=".1"/><stop offset="1" stop-color="#0B7765" stop-opacity=".28"/></linearGradient></defs><rect x="72" y="72" width="880" height="880" rx="196" fill="url(#tile)"/><rect x="78" y="78" width="868" height="868" rx="190" fill="none" stroke="url(#rim)" stroke-width="8"/><g transform="translate(128 128) scale(3)">${paths(C.ink,small)}</g>`,1024,1024,'Riftlet app icon — Passage');
}
const files={'mark.svg':mark(),'mark-light.svg':mark(C.paper),'mark-mono.svg':mark('#000000'),'mark-small.svg':mark(C.ink,true),'menu-bar.svg':mark('#000000',true),'menu-bar-light.svg':mark('#FFFFFF',true),'app-icon.svg':appIcon(),'favicon.svg':svg(`<rect x="8" y="8" width="240" height="240" rx="54" fill="${C.mint}"/>${paths(C.ink,true)}`)};
files['direction-a.svg']=svg(aPaths(),256,256,'Direction A — Split R, reserve candidate');
files['direction-c.svg']=svg(cPaths(),256,256,'Direction C — Inflection, not recommended');
files['app-icon-forest.svg']=appIcon().replace('#71E2C8','#24584E').replace(C.mint,'#17473E').replace('#23B598','#0D302A').replaceAll(`fill="${C.ink}"`,`fill="${C.paper}"`);
for(const [name,body] of Object.entries(files))fs.writeFileSync(path.join(out,name),body);
for(const name of ['mark.svg','mark-light.svg','app-icon.svg','favicon.svg'])fs.copyFileSync(path.join(out,name),path.join(assets,name));
async function main(){
 execFileSync('python3',[path.join(__dirname,'build-wordmark.py')],{stdio:'inherit'});
 const wordmark=fs.readFileSync(path.join(out,'wordmark.svg'),'utf8').match(/<g fill="#[A-Fa-f0-9]+">([\s\S]*?)<\/g>/)[1];
 const lockup=svg(`<g transform="translate(8 3) scale(.68)">${paths()}</g><g transform="translate(198 11) scale(.86)" fill="${C.ink}">${wordmark}</g>`,610,182,'Riftlet — horizontal brand lockup');
 fs.writeFileSync(path.join(out,'lockup.svg'),lockup);fs.writeFileSync(path.join(out,'lockup-light.svg'),lockup.replaceAll(C.ink,C.paper));
 await sharp(Buffer.from(lockup)).png().toFile(path.join(out,'lockup.png'));
 await sharp(path.join(out,'wordmark.svg')).png().toFile(path.join(out,'wordmark.png'));
 const sizes=[16,32,64,128,256,512,1024];
 for(const n of sizes){
  await sharp(Buffer.from(appIcon(n))).resize(n,n).png().toFile(path.join(out,`app-icon-${n}.png`));
  await sharp(Buffer.from(mark(C.ink,n<=32))).resize(n,n).png().toFile(path.join(out,`mark-${n}.png`));
 }
 for(const n of [16,32])for(const [suffix,color] of [['dark','#000000'],['light','#FFFFFF']])await sharp(Buffer.from(mark(color,true))).resize(n,n).png().toFile(path.join(out,`menu-bar-${suffix}-${n}.png`));
 await sharp(Buffer.from(files['app-icon-forest.svg'])).resize(512,512).png().toFile(path.join(out,'app-icon-forest-512.png'));
 const iconset=path.join(out,'AppIcon.iconset');fs.mkdirSync(iconset,{recursive:true});
 for(const logical of [16,32,128,256,512])for(const density of [1,2])fs.copyFileSync(path.join(out,`app-icon-${logical*density}.png`),path.join(iconset,`icon_${logical}x${logical}${density===2?'@2x':''}.png`));
 const chunks=[['icp4',16],['icp5',32],['icp6',64],['ic07',128],['ic08',256],['ic09',512],['ic10',1024],['ic11',32],['ic12',64]].map(([type,n])=>{const bytes=fs.readFileSync(path.join(out,`app-icon-${n}.png`));const h=Buffer.alloc(8);h.write(type,0,4,'ascii');h.writeUInt32BE(bytes.length+8,4);return Buffer.concat([h,bytes])});const icnsHead=Buffer.alloc(8);icnsHead.write('icns',0,4,'ascii');icnsHead.writeUInt32BE(8+chunks.reduce((n,x)=>n+x.length,0),4);fs.writeFileSync(path.join(out,'app-icon.icns'),Buffer.concat([icnsHead,...chunks]));
 const icoPNGs=await Promise.all([16,32,48].map(n=>sharp(Buffer.from(files['favicon.svg'])).resize(n,n).png().toBuffer()));
 const icoHeader=Buffer.alloc(6+icoPNGs.length*16);icoHeader.writeUInt16LE(1,2);icoHeader.writeUInt16LE(icoPNGs.length,4);let offset=icoHeader.length;
 [16,32,48].forEach((n,i)=>{const p=6+i*16;icoHeader[p]=n;icoHeader[p+1]=n;icoHeader.writeUInt16LE(1,p+4);icoHeader.writeUInt16LE(32,p+6);icoHeader.writeUInt32LE(icoPNGs[i].length,p+8);icoHeader.writeUInt32LE(offset,p+12);offset+=icoPNGs[i].length;});
 fs.writeFileSync(path.join(out,'favicon.ico'),Buffer.concat([icoHeader,...icoPNGs]));fs.copyFileSync(path.join(out,'favicon.ico'),path.join(assets,'favicon.ico'));
 const panel=svg(`<rect width="1200" height="720" fill="${C.paper}"/><g transform="translate(60 120) scale(1.7)">${paths()}</g><g transform="translate(650 80) scale(.52)">${appIcon().replace(/^.*?<svg[^>]*>/s,'').replace(/<\/svg>\s*$/,'')}</g><text x="74" y="620" fill="${C.ink}" font-family="sans-serif" font-size="26">PASSAGE / REFINED VECTOR</text><text x="74" y="657" fill="${C.ink}" font-family="sans-serif" font-size="16">One content plane. One quiet edge.</text>`,1200,720,'Passage vector and app icon');
 fs.writeFileSync(path.join(out,'passage-preview.svg'),panel);await sharp(Buffer.from(panel)).png().toFile(path.join(out,'passage-preview.png'));
 const board=svg(`<rect width="1536" height="1050" fill="${C.paper}"/><text x="72" y="76" fill="${C.ink}" font-family="sans-serif" font-size="27">RIFTLET / THREE INDEPENDENT DIRECTIONS</text><text x="72" y="111" fill="#55736A" font-family="sans-serif" font-size="16">Vector studies. Passage refined as the recommended candidate.</text><path d="M 512 165 V 956 M 1024 165 V 956" stroke="#D7DDD4"/><g transform="translate(112 204) scale(1.12)">${aPaths()}</g><g transform="translate(624 204) scale(1.12)">${paths()}</g><g transform="translate(1136 204) scale(1.12)">${cPaths()}</g><text x="72" y="584" fill="${C.ink}" font-family="sans-serif" font-size="23">01 / SPLIT R</text><text x="584" y="584" fill="${C.ink}" font-family="sans-serif" font-size="23">02 / PASSAGE</text><text x="1096" y="584" fill="${C.ink}" font-family="sans-serif" font-size="23">03 / INFLECTION</text><text x="72" y="623" fill="#55736A" font-family="sans-serif" font-size="16">A clearer initial.</text><text x="584" y="623" fill="#55736A" font-family="sans-serif" font-size="16">A content plane meets an edge.</text><text x="1096" y="623" fill="#55736A" font-family="sans-serif" font-size="16">A folded spatial gesture.</text><rect x="72" y="676" width="368" height="196" rx="26" fill="${C.mint}"/><rect x="584" y="676" width="368" height="196" rx="26" fill="${C.ink}"/><rect x="1096" y="676" width="368" height="196" rx="26" fill="#332A3C"/><g transform="translate(185 705) scale(.54)">${aPaths()}</g><g transform="translate(697 705) scale(.54)">${paths(C.paper)}</g><g transform="translate(1209 705) scale(.54)">${cPaths(C.warm)}</g><text x="72" y="928" fill="#55736A" font-family="sans-serif" font-size="15">Reserve / strong name association</text><text x="584" y="928" fill="${C.ink}" font-family="sans-serif" font-size="15">Recommended / mechanism-led identity</text><text x="1096" y="928" fill="#55736A" font-family="sans-serif" font-size="15">Eliminated / weaker product association</text>`,1536,1050,'Three Riftlet vector directions');
 fs.writeFileSync(path.join(out,'directions-board.svg'),board);await sharp(Buffer.from(board)).png().toFile(path.join(out,'directions-board.png'));
 const scaleHeader=svg(`<rect width="1536" height="1550" fill="${C.paper}"/><text x="60" y="64" fill="${C.ink}" font-family="sans-serif" font-size="26">PASSAGE / ACTUAL-SIZE EXPORT CHECK</text><text x="60" y="104" fill="#55736A" font-family="sans-serif" font-size="16">16 / 32 optical master · 64–1024 regular master · shown at their exported pixel dimensions</text><rect x="40" y="130" width="1456" height="250" rx="24" fill="#E3E9E1"/><text x="60" y="432" fill="${C.ink}" font-family="sans-serif" font-size="18">1024 px / full vector master</text><text x="1152" y="432" fill="${C.ink}" font-family="sans-serif" font-size="18">Monochrome / 16–256</text><rect x="1134" y="469" width="356" height="980" rx="20" fill="${C.ink}"/>`,1536,1550,'Riftlet exports at native dimensions');
 const scaleImgs=[];let x=65;
 for(const n of [16,32,64,128,256]){scaleImgs.push({input:path.join(out,`app-icon-${n}.png`),left:x,top:150+Math.round((210-n)/2)});x+=n+40;}
 scaleImgs.push({input:path.join(out,'app-icon-1024.png'),left:55,top:466});
 let sy=505;for(const n of [16,32,64,128,256]){scaleImgs.push({input:await sharp(Buffer.from(mark(C.paper,n<=32))).resize(n,n).png().toBuffer(),left:1184,top:sy});sy+=n+34;}
 await sharp(Buffer.from(scaleHeader)).composite(scaleImgs).png().toFile(path.join(out,'scale-check.png'));
 const review512=svg(`<rect width="1100" height="580" fill="${C.paper}"/><g transform="translate(20 25) scale(.5)">${appIcon().replace(/^.*?<svg[^>]*>/s,'').replace(/<\/svg>\s*$/,'')}</g><g transform="translate(570 25) scale(2)">${paths()}</g>`,1100,580,'512 pixel app icon and mark');await sharp(Buffer.from(review512)).png().toFile(path.join(out,'scale-512.png'));
 console.log(JSON.stringify({created:Object.keys(files),sizes,root:out}));
}
main().catch(e=>{console.error(e);process.exit(1)});
