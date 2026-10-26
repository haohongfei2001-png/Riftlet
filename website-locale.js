/* Language enhancement only. Does not change archived geometry or demo state. */
(() => {
  'use strict';
  const copy = {
  "交互": "Experience",
  "配色": "Colour",
  "视觉方向研究 · 2026": "Art direction · 2026",
  "截图 · 剪贴板 · 屏幕边缘": "SCREENSHOTS · CLIPBOARD · SCREEN EDGE",
  "不必找。": "No searching.",
  "就在那儿。": "Right there.",
  "刚刚截下、刚刚复制的内容，": "What you just captured or copied,",
  "安静地留在手边。记住位置，轻点取用。": "quietly close at hand. Remember the place. Click to use.",
  "体验边缘交互": "Try the interaction",
  "看看配色关系": "Explore the colours",
  "预发布设计展示，客户端尚未开放下载。所有示例内容均为合成。": "Prelaunch design preview. The app is not yet available. All examples are synthetic.",
  "为刚刚的内容，": "For what you just captured,",
  "留一个熟悉的位置。": "a familiar place.",
  "遮挡关系放大研究 · 不代表常驻界面的尺寸或角度": "Enlarged spatial study — not the scale or angle of the actual interface.",
  "让位置成为线索，": "Let position be the cue.",
  "让界面退到边缘。": "Let the interface step aside.",
  "内容可以只露出一部分。没有文件名、标题和工具栏，": "Just a glimpse of the content. No filenames, titles or toolbar.",
  "不用先展开一个容器。空间关系就是取用方式。": "No container to open first. Its place is how you reach it.",
  "常用的两三项，足够构成一个很小的日常习惯。": "Two or three recent items. One small everyday habit.",
  "实际尺度的交互研究": "A SMALL-SCALE INTERACTION STUDY",
  "漂亮，也要在这一小角成立。": "It has to work in this small corner, too.",
  "点击右侧任一缩略图。它会等待模拟附件就绪后才消失；失败会回原位。已有输入文字不会被改动。": "Click a thumbnail on the right. It disappears only after simulated readiness; a failure returns it to its place. Your draft text stays intact.",
  "演示桌面": "Demo desktop",
  "输入框": "Composer",
  "对话草稿 · 模拟界面": "Conversation draft · simulation",
  "继续你的工作。": "Stay with your work.",
  "Riftlet 只负责把刚刚的内容送到手边。": "Riftlet keeps what you just captured close at hand.",
  "模拟草稿，可自由编辑，内容不会被发送": "Editable simulated draft. Nothing is sent.",
  "只进入草稿": "Added to the draft only",
  "不会自动发送": "Never sent automatically",
  "右侧的 1、2、3 是待用截图。点击其中一项即可演示。": "Screenshots 1, 2 and 3 are waiting on the right. Click one to try it.",
  "模拟结果": "Simulated result",
  "成功": "Success",
  "明确失败": "Definite failure",
  "结果未知": "Unknown result",
  "重置示例": "Reset demo",
  "深色桌面": "Dark desktop",
  "浅色桌面": "Light desktop",
  "这是离线浏览器模拟：不读取系统截图或剪贴板，不连接 ChatGPT，不执行上传。缩略图最长边为 48 CSS px、外露区域为 29 CSS px；不是 macOS 逻辑点的实机标定。等待时长仅为演示。指针留在队列上时不填补空位，移开后再整理。未知项不会再次派发。": "Browser-local simulation: no screenshot or clipboard access, no ChatGPT connection and no uploads. Thumbnails are at most 48 CSS px with 29 CSS px exposed, not calibrated macOS points. Timing is illustrative. Positions stay put while the pointer is over the queue; unknown results are never blindly retried.",
  "品牌颜色，不是界面涂色": "BRAND COLOUR, NOT AN INTERFACE WASH",
  "青绿负责识别，近白色负责呼吸，杏色只提供一点冷暖对照。墨色把整个体系收住，而不是靠光晕和渐变制造“高级感”。": "Teal gives it identity. Off-white gives it space. A little apricot adds warmth. Ink holds it together, without relying on glows or gradients.",
  "保留青绿，但不把六个孤立色块当成设计。真正要比较的是颜色、比例、形体与交互放在一起之后的效果。": "Keep the teal, but do not mistake six swatches for a design. Colour, proportion, shape and interaction belong together.",
  "近白底色": "Off-white",
  "大面积承载，不额外做仿旧纸纹。": "An open surface. No artificial paper texture.",
  "墨色": "Ink",
  "文字、结构、主要按钮。": "Text, structure and primary actions.",
  "青绿主色": "Teal",
  "图标和少量品牌色块。": "The mark and a few deliberate accents.",
  "深青交互": "Deep teal",
  "浅底文字、链接与焦点。": "Text, links and focus on light surfaces.",
  "浅青": "Pale teal",
  "有限面积的材质与层次。": "A little material and depth.",
  "杏色": "Apricot",
  "品牌画面中的少量对照，不承担错误或成功状态。": "A small warm counterpoint, not an error or success signal.",
  "同一种关系，不同尺度": "ONE RELATIONSHIP, DIFFERENT SCALES",
  "大处有个性。": "Distinctive at a glance.",
  "小处不打扰。": "Quiet at the edge.",
  "图形用一条明确的间隙组织前后关系，字标、官网意象和小尺寸标记沿用相同结构。它们不必长得一模一样，但不应该像三个互不相关的产品。": "A deliberate gap separates foreground and background. The wordmark, website and small-scale mark share that relationship, without needing to look identical.",
  "当前字标与 R 形图形是本次新做的形体研究，不是已批准的正式 Logo。文字使用本机字体栈；不同设备会有字形差异，未嵌入任何字体文件。": "The wordmark and R-shaped symbol are studies, not approved final assets. Fonts use local system stacks and vary by device. No font files are embedded.",
  "记得它在哪里，": "Remember where it is.",
  "然后忘记工具本身。": "Then forget the tool.",
  "这份研究只回答一个问题：Riftlet 能否从“选一个好看的颜色”，走向属于自己的完整视觉语言。": "This study asks one question: can Riftlet move beyond a pleasing colour into a visual language of its own?",
  "它仍是一份可被否决、可继续精修的方向稿。": "An art direction to evaluate and refine, not a final verdict.",
  "研究范围": "Preview scope",
  "本页按原视觉研究稿还原。客户端尚未开放下载，所有附件状态均为本地模拟；不会读取系统截图、剪贴板或私人对话，也不会发送消息。图形仍是设计候选，不代表最终应用图标。": "Restored from the original art-direction study. The app is not yet available. All attachment states are local simulations; no screenshots, clipboard contents or private conversations are read, and nothing is sent. The mark is not a final app icon.",
  "开发进展": "Development",
  "Geist · Anthropic 案例": "Geist · Anthropic",
  "mymind · 设计原则": "mymind · Principles",
  "mymind 官网": "mymind",
  "W3C · 对比度": "W3C · Contrast",
  "Riftlet · Art direction preview · 所有功能与附件状态均为模拟": "Riftlet · Art direction preview · All functionality and attachment states are simulated",
  "准备中…": "Preparing…",
  "已就绪 · 模拟": "Ready · simulated"
};
  const patterns = [
    [/^截图 (\d+)$/, n => `Screenshot ${n}`],
    [/^插入截图 (\d+)，模拟操作，不发送消息$/, n => `Insert screenshot ${n}. Simulation only; nothing is sent.`],
    [/^移除模拟草稿中的截图 (\d+)$/, n => `Remove screenshot ${n} from the simulated draft`],
    [/^截图 (\d+) 已就绪并收起$/, n => `Screenshot ${n} is ready and tucked away`],
    [/^截图 (\d+) 明确失败，点击重试$/, n => `Screenshot ${n} failed. Click to retry.`],
    [/^截图 (\d+) 结果未知，保留且不自动重试$/, n => `Screenshot ${n}: unknown result. Retained without an automatic retry.`],
    [/^截图 (\d+) 的上次结果仍未知。原位置保留，不重新派发；此演示可用“重置示例”恢复。$/, n => `The previous result for screenshot ${n} is unknown. It stays in place and will not be sent again. Reset the demo to start over.`],
    [/^截图 (\d+) 已进入演示队列。其他项的位置保持不变。$/, n => `Screenshot ${n} is queued. Other items stay in place.`],
    [/^正在准备截图 (\d+) 的模拟附件；尚未确认成功，缩略图不会消失。$/, n => `Preparing simulated attachment ${n}. Its thumbnail stays until readiness is confirmed.`],
    [/^已从模拟草稿移除截图 (\d+)。队列不会无条件重新投递。$/, n => `Screenshot ${n} was removed from the simulated draft. It is not automatically reinserted.`],
    [/^截图 (\d+) 已在模拟草稿中就绪，完成吞噬。文字保留，没有发送消息。$/, n => `Screenshot ${n} is ready in the simulated draft and has tucked away. Your text is unchanged; nothing was sent.`],
    [/^截图 (\d+) 明确失败，已回到原位置。可把模拟结果改为“成功”后再次点击。$/, n => `Screenshot ${n} failed and returned to its place. Choose Success and click it to retry.`],
    [/^截图 (\d+) 的结果无法确认：保留原图和位置，不自动重传，也不表现为成功。$/, n => `Screenshot ${n} could not be confirmed. It stays in place, without a retry or a false success.`]
  ];
  function translate(raw) {
    const key = raw.trim();
    let value = copy[key];
    if (value === undefined) for (const [pattern, make] of patterns) {
      const match = key.match(pattern);
      if (match) { value = make(match[1]); break; }
    }
    return value === undefined ? raw : raw.replace(key, value);
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = {translate, copy};
  if (typeof document === 'undefined') return;
  const button = document.getElementById('language-toggle');
  if (!button) return;
  let language = 'zh';
  const originals = new WeakMap();
  const attributeOriginals = new WeakMap();
  function applyText(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      if (node.parentElement?.closest('script,style,textarea,svg,#language-toggle')) continue;
      let record = originals.get(node);
      if (!record || (node.nodeValue !== record.zh && node.nodeValue !== record.en)) {
        record = {zh: node.nodeValue, en: translate(node.nodeValue)};
        originals.set(node, record);
      }
      const next = language === 'en' ? record.en : record.zh;
      if (node.nodeValue !== next) node.nodeValue = next;
    }
    const labelled = [...root.querySelectorAll('[aria-label]')];
    if (root.hasAttribute?.('aria-label')) labelled.unshift(root);
    for (const element of labelled) {
      if (element === button || element.closest('svg')) continue;
      const current = element.getAttribute('aria-label');
      let record = attributeOriginals.get(element);
      if (!record || (current !== record.zh && current !== record.en)) {
        record = {zh: current, en: translate(current)};
        attributeOriginals.set(element, record);
      }
      const next = language === 'en' ? record.en : record.zh;
      if (current !== next) element.setAttribute('aria-label', next);
    }
  }
  button.addEventListener('click', () => {
    language = language === 'zh' ? 'en' : 'zh';
    document.documentElement.lang = language === 'en' ? 'en' : 'zh-CN';
    document.title = language === 'en' ? 'Riftlet — No searching. Right there.' : 'Riftlet — 不必找。就在那儿。';
    button.textContent = language === 'en' ? '中文' : 'English';
    button.setAttribute('aria-label', language === 'en' ? '切换为中文' : 'Switch to English');
    applyText(document.body);
  });
  const roots = ['status', 'attachments', 'edge-items', 'theme'].map(id => document.getElementById(id)).filter(Boolean);
  const observer = new MutationObserver(() => {
    if (language === 'en') roots.forEach(applyText);
  });
  roots.forEach(root => observer.observe(root, {childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['aria-label']}));
})();
