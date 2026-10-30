from pathlib import Path
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright
from PIL import Image, ImageChops
import base64,json,hashlib
R=Path(__file__).resolve().parents[1]
def inline(path):
 h=BeautifulSoup(path.read_text(),'html.parser')
 for x in h.select('link[rel=stylesheet]'):
  y=h.new_tag('style');y.string=(path.parent/x['href'].split('?')[0]).read_text();x.replace_with(y)
 for x in h.select('script[src]'):
  y=h.new_tag('script');y.string=(path.parent/x['src']).read_text();x.decompose();h.body.append(y)
 for x in h.select('img[src]'):
  if not x['src'].startswith('data:'):
   x['src']='data:image/svg+xml;base64,'+base64.b64encode((path.parent/x['src']).read_bytes()).decode()
 for x in h.select('link[rel=icon],link[rel=manifest]'):x.decompose()
 return str(h)
results=[]
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
 for v in ['A','B']:
  for w,h in [(1440,1000),(390,844)]:
   page=b.new_page(viewport={'width':w,'height':h},device_scale_factor=1,reduced_motion='reduce');page.route('**/*',lambda r:r.abort());page.goto('about:blank?variant='+v.lower())
   page.set_content(inline(R/f'{v}.html'));page.evaluate('document.fonts.ready');page.wait_for_timeout(200)
   img=R/'previews'/f'{v}-{w}-modular.png';page.screenshot(path=str(img))
   a=Image.open(img).convert('RGB');c=Image.open(R/'previews'/f'{v}-{w}.png').convert('RGB');bbox=ImageChops.difference(a,c).getbbox()
   results.append({'variant':v,'width':w,'class':page.locator('body').get_attribute('class'),'exact_pixel_match':bbox is None,'difference_bbox':bbox});page.close()
 for v in ['A','B']:
  page=b.new_page(viewport={'width':1440,'height':1000},device_scale_factor=1,reduced_motion='no-preference');page.route('**/*',lambda r:r.abort());page.set_content((R/f'Riftlet-{v}.html').read_text());page.wait_for_timeout(350)
  page.locator('.hero-shot[data-id="1"]').click();page.wait_for_timeout(420)
  state=page.evaluate('RiftletDemo.snapshot().items[0]');opacity=page.locator('.hero-shot[data-id="1"] svg').evaluate('(e)=>getComputedStyle(e).opacity');duration=page.locator('.hero-shot[data-id="1"] svg').evaluate('(e)=>getComputedStyle(e).transitionDuration')
  results.append({'variant':v,'normal_motion_swallow':state['state']=='started' and opacity=='0','transitionDuration':duration});page.wait_for_timeout(750);page.close()
 b.close()
(R/'docs'/'portable-results.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
if not all(x.get('exact_pixel_match',x.get('normal_motion_swallow',False)) for x in results):raise SystemExit(1)
