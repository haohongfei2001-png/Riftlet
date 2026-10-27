/* All screenshots are synthetic. Canvas is used for exact, editable software content. */
(function () {
  'use strict';
  const formats = [
    { label: '研究笔记 · 论证结构', width: 1600, height: 1000, kind: 'paper' },
    { label: '界面实现 · Layout.swift', width: 1920, height: 1080, kind: 'code' },
    { label: '阅读摘录 · 竖向截图', width: 1080, height: 1920, kind: 'notes' },
    { label: '周计划 · 表格', width: 1600, height: 900, kind: 'sheet' },
    { label: '观测数据 · 曲线', width: 1440, height: 900, kind: 'chart' },
    { label: '时间轴 · 超宽截图', width: 2400, height: 400, kind: 'timeline' },
    { label: '色彩研究 · 方形', width: 1000, height: 1000, kind: 'palette' },
    { label: '移动端阅读 · 长截图', width: 1170, height: 2532, kind: 'mobile' },
    { label: '资料目录 · Finder', width: 1500, height: 1000, kind: 'finder' },
    { label: '页面批注 · 设计草稿', width: 1200, height: 1600, kind: 'paper' },
    { label: '函数关系 · 宽幅图表', width: 2160, height: 960, kind: 'chart' },
    { label: '文字片段 · 极窄截图', width: 420, height: 1600, kind: 'notes' }
  ];
  let serial = 0;
  const cache = new Map();
  const font = '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
  function rr(ctx,x,y,w,h,r=12,fill='#fff',stroke) {
    ctx.beginPath(); ctx.roundRect(x,y,w,h,r); if(fill){ctx.fillStyle=fill;ctx.fill();} if(stroke){ctx.strokeStyle=stroke;ctx.stroke();}
  }
  function text(ctx,s,x,y,size=24,color='#26302e',weight=400) { ctx.font=weight+' '+size+'px '+font; ctx.fillStyle=color; ctx.fillText(s,x,y); }
  function line(ctx,x,y,x2,y2,color='#dfe4e0',width=1){ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x2,y2);ctx.strokeStyle=color;ctx.lineWidth=width;ctx.stroke();}
  function chrome(ctx,w,title,dark=false){ctx.fillStyle=dark?'#272930':'#f2f2ef';ctx.fillRect(0,0,w,64);['#ff6057','#febc2e','#28c840'].forEach((v,i)=>{ctx.beginPath();ctx.arc(25+i*27,30,8,0,Math.PI*2);ctx.fillStyle=v;ctx.fill();});text(ctx,title,w*.5-100,38,21,dark?'#c9ccd3':'#646864');line(ctx,0,63,w,63,dark?'#393c45':'#dedfd9');}
  function paragraph(ctx,x,y,w,count=8,size=23){const lines=['理解一个界面，需要观察它如何嵌入日常工作。','让每一个动作都留下清晰、可信的反馈。','从真实内容出发，保持比例与顺序，减少额外解释。','在不打断思考的前提下，把下一步自然地交给使用者。','最小的界面，也应当容纳完整的意图。','这是用于交互评审的合成内容，不含个人资料。'];for(let i=0;i<count;i++){const s=lines[i%lines.length];text(ctx,s.slice(0,Math.max(7,Math.floor(w/size))),x,y+i*size*1.9,size,'#4d5753');}}
  function draw(f){
    const c=document.createElement('canvas');c.width=f.width;c.height=f.height;const ctx=c.getContext('2d');const w=c.width,h=c.height;
    ctx.fillStyle='#fafbf8';ctx.fillRect(0,0,w,h);
    const sx=w/1600,sy=h/1000;
    if(f.kind==='code'){
      ctx.fillStyle='#20232b';ctx.fillRect(0,0,w,h);chrome(ctx,w,'Riftlet — Layout.swift',true);
      ctx.fillStyle='#1b1e24';ctx.fillRect(0,64,w*.19,h);text(ctx,'EXPLORER',25,116,21,'#969cac');
      ['RIFTLET','  Sources','    RiftletUI','      RiftLayout.swift','      Configuration.swift','    RiftletCore','  Tests','  Package.swift'].forEach((s,i)=>text(ctx,s,28,180+i*47,22,i===3?'#d1e2df':'#9ba3b3'));
      const code=['import Foundation','import RiftletCore','','public struct RiftRowLayout {','    let assetID: UUID','    let ordinal: Int','    let frame: CGRect','    let imageClipFrame: CGRect','}','','// Preserve the original aspect ratio.','let ratio = min(72 / width, 56 / height)','let fitted = CGSize(width: width * ratio,','                    height: height * ratio)','','// A received placeholder is not completion.','if receipt.isVerified {','    renderCommittedState()','}'];
      code.forEach((s,i)=>{text(ctx,String(i+1),w*.21,125+i*42,22,'#626b7e');text(ctx,s,w*.25,125+i*42,27,s.startsWith('//')?'#819783':s.includes('let')?'#b5c8e8':s.includes('if')?'#cfb2dc':'#d0d7e1');});
    } else if(f.kind==='sheet'){
      chrome(ctx,w,'工作计划 — 合成测试');text(ctx,'本周工作计划',42,118,30,'#293e34',600);ctx.fillStyle='#2c7056';ctx.fillRect(0,153,w,48);
      const cols=[0,.07,.39,.59,.8,1].map(v=>v*w);['','事项','负责人','状态','优先级'].forEach((s,i)=>text(ctx,s,cols[i]+20,185,21,'#fff'));
      const tasks=['整理界面参数','检查图片比例','补充操作反馈','核对队列编号','体验深色环境','记录第一轮观察','准备后续比较','处理已确认问题','整理演示素材','建立版本检查点'];
      tasks.forEach((s,i)=>{const y=202+i*59;ctx.fillStyle=i%2?'#f0f5ef':'#fff';ctx.fillRect(0,y,w,59);text(ctx,String(i+1),25,y+37,20,'#738276');text(ctx,s,cols[1]+20,y+37,23);text(ctx,'设计组',cols[2]+20,y+37,21,'#64766a');rr(ctx,cols[3]+15,y+13,98,32,16,i<3?'#e1ece0':'#f4ecd4');text(ctx,i<3?'已完成':'进行中',cols[3]+28,y+35,18,i<3?'#52764d':'#987c34');text(ctx,i<4?'高':'普通',cols[4]+20,y+37,21);});cols.forEach(x=>line(ctx,x,201,x,h,'#dce4db'));
    } else if(f.kind==='chart'){
      chrome(ctx,w,'Analysis · 合成观察');text(ctx,'从输入到确认',w*.07,150*sy,44*sy,'#253e38',600);text(ctx,'独立样本 / 正常化显示 · 非真实测量数据',w*.07,198*sy,24*sy,'#7b8580');
      const left=w*.09,right=w*.92,top=h*.32,bottom=h*.81;
      for(let i=0;i<6;i++){const y=top+(bottom-top)*i/5;line(ctx,left,y,right,y);text(ctx,(100-i*20)+'',left-50,y+7,19,'#87908b');}
      ['输入','响应','传输','观察','确认'].forEach((s,i)=>text(ctx,s,left+(right-left)*i/4-22,bottom+45,21,'#64756e'));
      ['#3c8279','#bc9468','#8798ae'].forEach((col,k)=>{ctx.beginPath();for(let i=0;i<=160;i++){const x=left+(right-left)*i/160;const v=.7*Math.exp(-i/60)*(1+.11*Math.sin(i/8+k))+k*.08;const y=bottom-v*(bottom-top);if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y);}ctx.strokeStyle=col;ctx.lineWidth=4;ctx.stroke();});
      rr(ctx,w*.69,h*.38,w*.19,h*.15,12,'#fff','#e3e8e2');text(ctx,'样本 03',w*.71,h*.43,22,'#87948d');text(ctx,'0.742 ± 0.018',w*.71,h*.49,28,'#365e52',600);
    } else if(f.kind==='timeline'){
      text(ctx,'PROJECT NOTES',44,65,24,'#6d7975',500);text(ctx,'一次动作，完整的反馈',44,125,39,'#293d36',600);
      const labels=['截图产生','图片收录','按下微图','传输等待','附件确认','完成吞噬'];line(ctx,82,236,w-100,236,'#b1c5bb',3);
      labels.forEach((s,i)=>{const x=90+i*(w-210)/5;ctx.beginPath();ctx.arc(x,236,10,0,Math.PI*2);ctx.fillStyle=i===4?'#3d7464':'#91ada0';ctx.fill();text(ctx,String(i+1).padStart(2,'0'),x-10,204,18,'#81958a');text(ctx,s,x-40,292,25);});
    } else if(f.kind==='palette'){
      text(ctx,'COLOUR / MATERIAL',60,85,23,'#6d7c74');text(ctx,'安静地存在',60,163,51,'#29453a',600);
      const cols=['#21564c','#497b6c','#a5baae','#e9e9df','#c6b29b','#323f3b'];cols.forEach((co,i)=>{const x=60+i%3*300,y=230+Math.floor(i/3)*290;rr(ctx,x,y,260,230,0,co);text(ctx,co.toUpperCase(),x,y+264,20,'#697d70');});
      text(ctx,'合成色彩样本 · 不代表正式品牌裁定',60,940,20,'#79847f');
    } else if(f.kind==='finder'){
      chrome(ctx,w,'设计资料');ctx.fillStyle='#eef0eb';ctx.fillRect(0,64,w*.21,h);['个人收藏','最近使用','桌面','文稿','下载','设计资料','位置','本机'].forEach((s,i)=>text(ctx,s,32,125+i*62,i===0||i===6?18:24,'#6f7b72'));
      const labels=['界面参数','初轮观察','交互记录','图像样本','产品说明','候选归档','验收清单','工作笔记','参考资料'];labels.forEach((s,i)=>{const x=w*.27+i%3*w*.235,y=115+Math.floor(i/3)*250;rr(ctx,x,y+20,118,90,10,'#7ebad5');rr(ctx,x+4,y+3,53,30,6,'#94c7dd');text(ctx,s,x-2,y+154,23,'#4f5c55');text(ctx,'合成文件夹',x+3,y+183,17,'#8a958c');});
    } else if(f.kind==='mobile'){
      const sc=w/1170;ctx.save();ctx.scale(sc,sc);text(ctx,'9:41',75,80,35,'#1f2924',600);text(ctx,'•••  ▰',950,80,28);line(ctx,0,125,1170,125);text(ctx,'阅读',80,220,44,'#203d32',600);text(ctx,'让工具退到思考之后',80,367,67,'#243b30',600);text(ctx,'设计笔记 / 06',82,441,30,'#89968c');
      rr(ctx,80,520,1010,510,6,'#dce5d9');ctx.fillStyle='#9eb8a6';ctx.beginPath();ctx.moveTo(80,940);ctx.lineTo(400,630);ctx.lineTo(650,920);ctx.lineTo(860,710);ctx.lineTo(1090,975);ctx.closePath();ctx.fill();text(ctx,'观察，是设计真正开始的地方。',90,1130,40,'#3b5749',500);paragraph(ctx,80,1240,1000,13,37);ctx.restore();
    } else {
      const narrow=w<600;const m=narrow?35:w*.09;chrome(ctx,w,f.kind==='notes'?'Notes · 合成摘录':'Preview · 研究笔记');
      text(ctx,f.kind==='notes'?'观察笔记':'界面与注意力',m,Math.min(180,h*.14),narrow?28:Math.min(47,w*.04),'#2c4236',600);
      text(ctx,'2026 / 10 / 27    SYNTHETIC',m,Math.min(225,h*.19),narrow?15:20,'#879489');
      if(f.kind==='paper'){
        const y=h*.31;rr(ctx,m,y,w-2*m,h*.22,0,'#eef2eb');text(ctx,'T = t₁ + t₂ + t₃',m+30,y+65,34,'#385c49');text(ctx,'输入 → 可见 → 确认',m+30,y+125,25,'#6f8474');paragraph(ctx,m,y+h*.29,w-2*m,7,24);
      }else {paragraph(ctx,m,300,w-2*m,Math.floor((h-330)/65),narrow?22:30);}
    }
    text(ctx,'RIFTLET  /  SYNTHETIC REVIEW FIXTURE',Math.max(15,w*.035),h-20,Math.max(11,Math.min(16,w/70)),'#89988e');
    return c.toDataURL('image/png');
  }
  window.RiftAssets={
    formats,
    create(index){const n=Number.isFinite(index)?index:serial;const fi=((n%formats.length)+formats.length)%formats.length;const f=formats[fi];if(!cache.has(fi))cache.set(fi,draw(f));serial++;return{id:'capture-'+Date.now().toString(36)+'-'+serial,label:f.label,width:f.width,height:f.height,src:cache.get(fi),kind:f.kind};},
    reset(){serial=0;},
    batch(n){return Array.from({length:n},(_,i)=>this.create(i));}
  };
})();
