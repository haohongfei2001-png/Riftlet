import Foundation

/// A short-lived isolated-world document/node witness, not a TargetLease or an
/// upload admission. MAIN still proves the business composer and binds the pin.
/// Any observed route/node change burns this witness; restoring the URL/nodes
/// does not restore it. No text, selection, image or URL is returned to native.
enum ClickDocumentWitness {
    static func install(_ id: UUID) -> String {
        let key = id.uuidString.lowercased()
        return """
        (()=>{
          const root=document.documentElement,key='data-riftlet-pending-\(key)';
          if(document.visibilityState!=='visible'||!document.hasFocus()||globalThis.top!==globalThis)return 'unavailable';
          const editors=[...document.querySelectorAll('[contenteditable=true][role=textbox][aria-label="询问 ChatGPT"]')];
          if(editors.length!==1)return 'unavailable';
          const editor=editors[0],form=editor.closest('form');
          const inputs=form?[...form.querySelectorAll('input[type=file][aria-label="附加文件"]')]:[];
          if(!form||inputs.length!==1||!editor.isConnected||!inputs[0].isConnected)return 'unavailable';
          const input=inputs[0],route=location.href;
          if([...root.attributes].filter(a=>a.name.startsWith('data-riftlet-pending-')).length>=16)return 'unavailable';
          for(const n of [root,form,editor,input])n.setAttribute(key,'ready');
          let alive=true;
          const stop=()=>{if(!alive)return;alive=false;observer.disconnect();root.removeEventListener('riftlet-validate-\(key)',validate);root.removeEventListener('riftlet-release-\(key)',stop);
            for(const n of [root,form,editor,input])n.removeAttribute(key);
            for(const event of ['pagehide','popstate','hashchange'])globalThis.removeEventListener(event,stop,true);
            globalThis.navigation?.removeEventListener('navigate',stop);};
          const bad=records=>document.documentElement!==root||location.href!==route||!form.isConnected||!editor.isConnected||!input.isConnected
            ||editor.closest('form')!==form||input.form!==form
            ||records.some(r=>r.type==='childList' && [...r.removedNodes].some(n=>n===form||n===editor||n===input||n.contains?.(form)||n.contains?.(editor)||n.contains?.(input))
              ||(form.contains(r.target)&&(r.type!=='attributes'||!r.attributeName?.startsWith('data-riftlet-'))));
          const observer=new MutationObserver(records=>{if(bad(records))stop();});
          const validate=()=>{if(!alive||bad(observer.takeRecords())){stop();return;}
            root.setAttribute(key,'validated');};
          root.addEventListener('riftlet-validate-\(key)',validate);
          root.addEventListener('riftlet-release-\(key)',stop);
          observer.observe(root,{subtree:true,childList:true,attributes:true,characterData:true});
          for(const event of ['pagehide','popstate','hashchange'])globalThis.addEventListener(event,stop,true);
          globalThis.navigation?.addEventListener('navigate',stop);
          setTimeout(stop,5000);
          return 'ready';
        })()
        """
    }
}
