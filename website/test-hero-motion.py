"""Regression: an entrance animation must not visually override the final swallow."""
import importlib.util
import json
import os
from pathlib import Path
from playwright.sync_api import sync_playwright

spec = importlib.util.spec_from_file_location('hero_fixture', Path(__file__).with_name('test-hero.py'))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
with sync_playwright() as p:
    opts = {'executable_path': os.environ['CHROMIUM_EXECUTABLE']} if os.environ.get('CHROMIUM_EXECUTABLE') else {}
    browser = p.chromium.launch(**opts)
    page = browser.new_page(viewport={'width': 1440, 'height': 1000}, reduced_motion='no-preference')
    page.route('**/*', lambda route: route.abort())
    page.set_content(fixture.document(), wait_until='load')
    page.wait_for_timeout(4300)
    shot = page.locator('[data-shot="3"]')
    assert shot.get_attribute('data-state') == 'done'
    visual = shot.locator('svg').evaluate('(n)=>({opacity:getComputedStyle(n).opacity,transform:getComputedStyle(n).transform,animation:getComputedStyle(n).animationName})')
    assert float(visual['opacity']) == 0, visual
    assert visual['animation'] == 'none', visual
    assert page.locator('#hero-attachments [data-ready="true"]').count() == 1
    browser.close()
print(json.dumps({'scope': 'in-memory Chromium with normal motion', 'passed': True, 'visual': visual}, indent=2))
