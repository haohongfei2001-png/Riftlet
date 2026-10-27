"""Regression: hero hint must not overlap the editable draft at any breakpoint."""
import importlib.util
import json
import os
from pathlib import Path
from playwright.sync_api import sync_playwright

spec = importlib.util.spec_from_file_location('hero_fixture', Path(__file__).with_name('test-hero.py'))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
results = []
with sync_playwright() as p:
    options = {'executable_path': os.environ['CHROMIUM_EXECUTABLE']} if os.environ.get('CHROMIUM_EXECUTABLE') else {}
    browser = p.chromium.launch(**options)
    for width in [320, 390, 768, 1024, 1440, 1920]:
        page = browser.new_page(viewport={'width': width, 'height': 1000}, reduced_motion='reduce')
        page.route('**/*', lambda route: route.abort())
        page.set_content(fixture.document(), wait_until='load')
        for lang in ['zh', 'en']:
            if lang == 'en': page.locator('#language-toggle').click()
            hint = page.locator('.hero-edge-hint')
            if hint.is_visible():
                a, b = hint.bounding_box(), page.locator('#hero-draft').bounding_box()
                separate = (a['x'] + a['width'] <= b['x'] or b['x'] + b['width'] <= a['x'] or
                            a['y'] + a['height'] <= b['y'] or b['y'] + b['height'] <= a['y'])
                assert separate, (width, lang, 'hint overlaps draft')
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
            results.append({'width': width, 'language': lang, 'hint_clear_of_draft': True})
        page.close()
    browser.close()
print(json.dumps({'scope': 'in-memory Chromium layout regression', 'passed': len(results), 'checks': results}, indent=2))
