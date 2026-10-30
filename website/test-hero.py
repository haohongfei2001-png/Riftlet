"""Browser tests of source bytes rendered in memory, not live-site/macOS evidence.
Requires Python + playwright and a Chromium executable. No server or network.
Run: CHROMIUM_EXECUTABLE=/usr/bin/chromium python website/test-hero.py
"""
import json, os, re
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
RESULTS = []

def document():
    html = (ROOT / 'index.html').read_text()
    html = re.sub(r'<link rel="stylesheet" href="([^"]+)">',
        lambda m: '<style>' + (ROOT / m[1].split('?')[0]).read_text() + '</style>', html)
    scripts = []
    def script(m):
        scripts.append((ROOT / m[1].split('?')[0]).read_text()); return ''
    html = re.sub(r'<script src="([^"]+)" defer></script>', script, html)
    def icon(m):
        attrs = m[0]
        svg = (ROOT / 'favicon.svg').read_text().strip()
        extra = ' '.join(re.findall(r'(?:class|width|height)="[^"]+"', attrs))
        return svg.replace('<svg ', '<svg ' + extra + ' aria-hidden="true" ', 1)
    html = re.sub(r'<img\b[^>]*src="favicon\.svg[^>]*>', icon, html)
    return html.replace('</body>', ''.join('<script>'+s+'</script>' for s in scripts)+'</body>')

def check(name, fn):
    fn(); RESULTS.append(name)

def main():
    html = document()
    with sync_playwright() as p:
        opts = {'executable_path': os.environ['CHROMIUM_EXECUTABLE']} if os.environ.get('CHROMIUM_EXECUTABLE') else {}
        browser = p.chromium.launch(**opts)
        def page(width=1440, height=1000, reduced=True, js=True):
            q=browser.new_page(viewport={'width':width,'height':height},device_scale_factor=1,
                reduced_motion='reduce' if reduced else 'no-preference',java_script_enabled=js)
            q.route('**/*',lambda r:r.abort())
            q.on('pageerror',lambda error: (_ for _ in ()).throw(AssertionError(str(error))))
            q.set_content(html,wait_until='load'); return q
        for width in [320,390,768,1024,1440,1920]:
            q=page(width)
            for lang in ['zh','en']:
                if lang=='en': q.locator('#language-toggle').click()
                assert q.evaluate('document.documentElement.scrollWidth <= innerWidth'), (width,lang,'overflow')
                assert q.locator('#hero-play').is_visible()
                assert q.locator('#hero-capture').is_visible()
                assert q.locator('[data-shot="1"]').is_visible()
                RESULTS.append(f'layout {width}px {lang}: no horizontal overflow and controls visible')
            q.close()
        q=page()
        q.wait_for_timeout(1300)
        assert q.locator('#hero-scene').get_attribute('data-phase')=='idle'
        RESULTS.append('reduced motion suppresses automatic playback')
        q.locator('#hero-draft').fill('保留我的文字 🧩\n第二行')
        q.locator('[data-shot="1"]').click()
        q.wait_for_timeout(360)
        assert q.locator('[data-shot="1"]').get_attribute('data-state')=='done'
        assert q.locator('#hero-attachments [data-ready="false"]').count()==1
        assert q.locator('#hero-attachments [data-ready="true"]').count()==0
        q.locator('[data-shot="1"]').evaluate('(b)=>b.click()')
        q.locator('#language-toggle').click()
        q.wait_for_timeout(750)
        assert q.locator('#hero-attachments .hero-attachment').count()==1
        assert q.locator('#hero-attachments [data-ready="true"]').count()==1
        assert q.locator('#hero-draft').input_value()=='保留我的文字 🧩\n第二行'
        RESULTS.append('pending/ready separation, duplicate suppression, locale and draft preservation')
        q.locator('#hero-capture').click()
        assert q.locator('#hero-attachments .hero-attachment').count()==1
        assert q.locator('[data-shot="3"]').get_attribute('data-state')=='available'
        assert q.locator('#hero-capture').is_disabled()
        RESULTS.append('new capture does not clear existing attachments or draft')
        q.locator('[data-shot="2"]').click();q.locator('[data-shot="3"]').click()
        q.wait_for_timeout(2300)
        ids=q.locator('#hero-attachments .hero-attachment').evaluate_all('(xs)=>xs.map(x=>x.dataset.id)')
        assert ids==['1','2','3'],ids
        RESULTS.append('three different screenshots attach once in click order')
        q.locator('#hero-play').click();q.wait_for_timeout(50)
        q.locator('#hero-play').click();q.wait_for_timeout(1400)
        assert q.locator('#hero-attachments .hero-attachment').count()==1
        assert q.locator('#hero-draft').input_value()=='保留我的文字 🧩\n第二行'
        RESULTS.append('restart invalidates stale work without changing user draft')
        q.close()
        q=page()
        q.locator('#hero-play').click();q.wait_for_timeout(420)
        q.locator('#hero-pause').click();q.wait_for_timeout(1200)
        assert q.locator('[data-shot="3"]').get_attribute('data-state')=='done'
        assert q.locator('#hero-attachments [data-ready="true"]').count()==1
        RESULTS.append('pausing narration does not cancel an already-started synthetic attachment')
        q.close()
        q=page()
        q.locator('#hero-capture').click()
        before=q.locator('[data-shot="2"]').evaluate('(n)=>n.getBoundingClientRect().top')
        q.locator('[data-shot="1"]').click();q.wait_for_timeout(1200)
        assert q.locator('[data-shot="2"]').evaluate('(n)=>n.getBoundingClientRect().top')==before
        q.mouse.move(10,10);q.wait_for_timeout(300)
        assert q.locator('[data-shot="2"]').evaluate('(n)=>n.getBoundingClientRect().top')<before
        RESULTS.append('pointer protects target slots; items compact after leaving')
        q.close()
        q=page()
        q.locator('#hero-capture').focus();q.keyboard.press('Enter')
        q.locator('[data-shot="3"]').focus();q.keyboard.press('Enter');q.wait_for_timeout(1200)
        assert q.locator('#hero-attachments [data-ready="true"]').count()==1
        RESULTS.append('keyboard capture and attachment')
        q.locator('#draft').fill('保留下方原有演示')
        q.locator('.rift-item[data-id="1"]').click();q.wait_for_timeout(1300)
        assert q.locator('#attachments .attachment').count()==1
        assert q.locator('#hero-attachments .hero-attachment').count()==1
        assert q.locator('#draft').input_value()=='保留下方原有演示'
        RESULTS.append('hero and existing lower demonstration are isolated')
        q.close()
        q=page(reduced=False)
        q.wait_for_timeout(4300)
        assert q.locator('#hero-attachments .hero-attachment').count()==1
        assert q.locator('#hero-scene').get_attribute('data-phase')=='ready'
        q.wait_for_timeout(1200)
        assert q.locator('#hero-attachments .hero-attachment').count()==1
        RESULTS.append('visible introduction plays once and rests, without looping')
        q.close()
        q=page(js=False)
        assert q.locator('.hero-source').is_visible()
        assert q.locator('#hero-draft').is_visible()
        assert '照常截图' in q.locator('body').inner_text()
        RESULTS.append('no-JavaScript fallback retains explanatory product scene')
        q.close();browser.close()
    print(json.dumps({'scope':'in-memory Chromium; no live navigation or native app claim',
        'passed':len(RESULTS),'tests':RESULTS},ensure_ascii=False,indent=2))

if __name__=='__main__':main()
