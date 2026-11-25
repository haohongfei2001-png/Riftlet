'use strict';

// Everything in this file belongs to the synthetic receiver. All images are
// generated locally and the browser test routes every request to this fixture.
function fixture(id, mode) {
  const field = '<input id="field" type="file" aria-label="Upload files">';
  const open = '<button type="button" aria-label="Attach files"></button>';
  const names = {claude:'Claude',copilot:'Microsoft Copilot',grok:'Grok',poe:'Poe',deepseek:'DeepSeek',spark:'iFlytek Spark',meta:'Meta AI',mistral:'Mistral Vibe'};
  const text = '<textarea aria-label="Message ' + (mode === 'genericNonChat' ? 'assistant' : names[id]) + '"></textarea>';
  const rich = '<div role="textbox" contenteditable="true">QA draft</div>';
  const examples = {
    gemini:['<fieldset class="input-area-fieldset">','<rich-textarea>' + rich.replace('role=','class="ql-editor" role=') + '</rich-textarea>','<button type="button" aria-haspopup="menu" aria-label="Upload &amp; tools"></button>','</fieldset>'],
    perplexity:['<div class="group/composer-row">',rich.replace('role=','aria-label="Ask anything…" role='),'<button type="button" aria-label="Add files, plugins, and more"></button>','</div>'],
    kimi:['<div class="chat-editor">',rich.replace('role=','class="chat-input-editor" role='),'<input type="file" class="hidden-input" id="field">','</div>'],
    qianwen:['<div id="input-island-owner">',rich,'<button type="button" aria-haspopup="menu" aria-label="添加附件"></button>','</div>'],
    qwen:['<div class="message-input-container">','<textarea class="message-input-textarea"></textarea>','<input type="file" id="filesUpload" aria-label="Upload files">','</div>'],
    doubao:['<div class="guidance-input-surface">',rich.replace('role=','class="tiptap" role='),'<button type="button" data-testid="upload_file_button"></button>','</div>'],
    yuanbao:['<section id="searchbar-editor">',rich.replace('role=','class="ql-editor" role='),'<button type="button" aria-label="Add"></button>','</section>'],
    qingyan:['<div class="chat-sender">','<textarea class="el-textarea__inner"></textarea>','<div class="upload-attachment-picker"><input type="file" class="file-input" id="field"></div>','</div>'],
    wenxin:['<div id="ci-main">','<textarea id="chat-textarea"></textarea>','<div class="ci-merge-upload-wrapper"><div id="ci-merge-upload-btn" style="width:26px;height:24px"></div></div>','</div>'],
    zai:['<div class="messageInputContainer">','<form><textarea id="chat-input"></textarea></form>',field,'</div>']
  };
  const generic = ['<form>',text,['menu','detached','focusTheft'].includes(mode) ? open : field,'</form>'];
  const [start,editor,entry,end] = examples[id] || generic;
  return '<!doctype html><meta charset="utf-8"><title>Isolated QA draft</title>' +
    '<style>button{display:inline-block;min-width:40px;min-height:20px}input[type=file]{display:none}img{width:28px;height:24px} [contenteditable=true]{min-height:30px}</style>' +
    '<aside><form><input type="file" id="avatar" aria-label="Upload avatar"></form></aside>' +
    '<main>' + start + editor + entry + '<div id="cards"><div data-filename="prior.png">prior.png</div></div><button type="submit" id="send">Send</button>' + end + '</main>';
}

function installFixture(mode) {
  const root = document.getElementById('cards').parentElement;
  const editor = root.querySelector('textarea,[contenteditable]');
  const counts = {setter:0,input:0,change:0,send:0,submit:0,avatar:0};
  const draft = 'QA preserve this original draft';
  let current, backwards;
  if ('value' in editor) {
    editor.value = draft; editor.focus(); editor.setSelectionRange(3,16,'backward');
    backwards = () => [editor.selectionStart,editor.selectionEnd,editor.selectionDirection];
  } else {
    editor.textContent = draft; editor.focus();
    const selection = getSelection();
    selection.setBaseAndExtent(editor.firstChild,16,editor.firstChild,3);
    backwards = () => [selection.anchorOffset,selection.focusOffset,selection.toString()];
  }
  const before = {text:draft,selection:backwards()};
  document.addEventListener('submit',e => { e.preventDefault(); counts.submit++; });
  document.getElementById('send').onclick = e => { e.preventDefault(); counts.send++; };
  const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files');
  Object.defineProperty(HTMLInputElement.prototype,'files',{...descriptor,set(files) {
    if (this.id === 'avatar') counts.avatar++;
    else counts.setter++;
    return descriptor.set.call(this,files);
  }});
  const cards = document.getElementById('cards');
  function png(value) {
    const canvas = document.createElement('canvas'); canvas.width = 40; canvas.height = 30;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = value; ctx.fillRect(0,0,40,30);
    return canvas.toDataURL();
  }
  function attach(input) {
    input.addEventListener('input',() => counts.input++);
    input.addEventListener('change',() => {
      counts.change++;
      if (mode === 'focusTheft') { editor.focus(); editor.setSelectionRange(0,0); }
      if (mode === 'noCard') return;
      const file = input.files[0];
      const card = document.createElement('figure');
      card.dataset.filename = file.name;
      const img = document.createElement('img'); img.alt = file.name;
      img.src = mode === 'differentPixels' ? png('lime') : URL.createObjectURL(file);
      if (mode === 'failure') {
        const failure = document.createElement('span'); failure.textContent = 'Upload failed'; card.append(failure);
      }
      if (mode === 'progress') {
        const progress = document.createElement('progress'); progress.value = 1; card.append(progress);
        const label = document.createElement('span'); label.textContent = 'Upload failed'; card.append(label);
      }
      card.append(img);
      const prior = cards.firstElementChild;
      if (mode === 'oldCardABA') { prior.remove(); cards.prepend(prior); }
      cards.append(card); current = card;
    });
    return input;
  }
  const field = root.querySelector('input[type=file]');
  if (field) attach(field);
  else {
    const opener = root.querySelector('button[type=button],#ci-merge-upload-btn');
    function requestChooser() {
      if (mode === 'focusTheft') { opener.focus(); editor.setSelectionRange(2,2); }
      const input = document.createElement('input'); input.type = 'file'; attach(input); input.click();
    }
    if (mode === 'menu') {
      opener.setAttribute('aria-haspopup','menu'); opener.setAttribute('aria-controls','files-menu');
      opener.onclick = () => {
        opener.setAttribute('aria-expanded','true');
        const menu = document.createElement('div'); menu.id = 'files-menu'; menu.setAttribute('role','menu');
        const action = document.createElement('button'); action.type = 'button'; action.textContent = 'Upload file';
        action.onclick = () => { requestChooser(); menu.remove(); };
        menu.append(action); document.body.append(menu);
      };
    } else opener.onclick = requestChooser;
  }
  window.fixture = {counts,before,png,editor,field,root,
    snapshot:() => ({text:'value' in editor ? editor.value : editor.textContent,selection:backwards(),
      old:cards.firstElementChild?.dataset.filename,filenames:Array.from(cards.children,c => c.dataset.filename),counts:{...counts}}),
    originalCardABA:() => { current.remove(); cards.append(current); current.dataset.state = 'error'; }};
}
module.exports = {fixture,installFixture};
