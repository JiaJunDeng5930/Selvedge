#!/usr/bin/env python3
"""Real Chromium image paste, model delivery and durable conversation rendering.

Run after the production build:
  BUN_BIN=/path/to/bun CHROMIUM_BIN=/path/to/chrome python3 scripts/test-images-browser.py
Requires Python Playwright. OAuth and model HTTP are local fixture peers.
"""
import argparse
import importlib
import json
import os
from pathlib import Path
import shutil
import time
from playwright.sync_api import sync_playwright, expect

driver = importlib.import_module('test-interactive-markdown-browser')
ROOT = Path(__file__).resolve().parents[1]
IMAGE = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg=='


def image_blocks(value):
    if isinstance(value, list):
        return [block for item in value for block in image_blocks(item)]
    if not isinstance(value, dict):
        return []
    if value.get('type') == 'input_image':
        return [value]
    return [block for item in value.values() for block in image_blocks(item)]


def model_request(fixture, count, images):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        status = fixture.call('/status')
        assert not status['failures'], status['failures']
        if len(status['requests']) >= count:
            request = status['requests'][count - 1]
            blocks = image_blocks(request.get('input'))
            assert len(blocks) == images, request
            assert all(block['image_url'] == 'data:image/png;base64,' + IMAGE for block in blocks), blocks
            return request
        time.sleep(.05)
    # DEFENSE: A browser upload or command regression can prevent a real provider request within the fixture deadline.
    raise AssertionError('No actual image model request: ' + json.dumps(fixture.call('/status')))


def paste_image(composer):
    composer.evaluate('''(node,base64)=>{
      const bytes=Uint8Array.from(atob(base64),character=>character.charCodeAt(0));
      const files=new DataTransfer();
      files.items.add(new File([bytes],'pasted red square.png',{type:'image/png'}));
      node.dispatchEvent(new ClipboardEvent('paste',{clipboardData:files,bubbles:true,cancelable:true}));
    }''', IMAGE)


def visible_images(page, count):
    images = page.locator('img[src^="/api/board/attachments/"]:not([inert] img)').filter(visible=True)
    expect(images).to_have_count(count)
    page.wait_for_function('''count=>{
      const images=[...document.querySelectorAll('img[src^="/api/board/attachments/"]')]
        .filter(image=>image.checkVisibility()&&!image.closest('[inert]'));
      return images.length===count&&images.every(image=>image.complete&&image.naturalWidth===2&&image.naturalHeight===2);
    }''', arg=count)


def message_composer(page):
    return page.locator('textarea[data-key$="/message"]:not([inert] textarea)').filter(visible=True)


def image_boundaries(page, fixture, artifacts):
    page.get_by_role('button', name='新建对话', exact=True).click()
    composer = message_composer(page)
    expect(composer).to_be_visible()
    composer.fill('Inspect the screenshot pasted into a new task.')
    paste_image(composer)
    visible_images(page, 1)
    page.get_by_role('button', name='Preview pasted red square.png', exact=True).filter(visible=True).click()
    preview = page.get_by_role('dialog').filter(visible=True)
    expect(preview).to_be_visible()
    visible_images(page, 1)
    page.screenshot(path=str(artifacts / 'images-preview.png'))
    page.keyboard.press('Escape')
    expect(preview).not_to_be_visible()
    visible_images(page, 1)
    composer.press('Enter')
    model_request(fixture, 1, 1)
    task = fixture.command(op='list')['tasks'][0]['id']
    fixture.idle(task)
    driver.navigate_task_id(page, task)
    visible_images(page, 1)

    composer = message_composer(page)
    expect(composer).to_have_value('')
    paste_image(composer)
    visible_images(page, 2)
    composer.press('Enter')
    model_request(fixture, 2, 2)
    fixture.idle(task)
    visible_images(page, 2)
    page.screenshot(path=str(artifacts / 'images-conversation.png'))

    fixture.call('/restart', {})
    page.reload(wait_until='domcontentloaded')
    driver.navigate_task_id(page, task)
    visible_images(page, 2)
    message_composer(page).fill('Read both saved images again.')
    message_composer(page).press('Enter')
    model_request(fixture, 3, 2)
    fixture.idle(task)
    visible_images(page, 2)
    page.screenshot(path=str(artifacts / 'images-recovered.png'))
    print(json.dumps({'boundary': 'new-task paste, image-only continuation, actual ChatGPT image bytes, restart and loaded image pixels', 'passed': True}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--chromium', default=os.environ.get('CHROMIUM_BIN') or shutil.which('chromium'))
    parser.add_argument('--artifacts', default=str(ROOT / '.workpad/images-browser-results'))
    args = parser.parse_args()
    # DEFENSE: A developer machine can lack Chromium, which this physical browser regression requires.
    if not args.chromium:
        raise RuntimeError('Chromium is required; set CHROMIUM_BIN')
    artifacts = Path(args.artifacts)
    artifacts.mkdir(parents=True, exist_ok=True)
    fixture = driver.Fixture('tests/fixtures/images.mjs')
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(executable_path=args.chromium, headless=True, args=['--no-sandbox'])
            context = browser.new_context(viewport={'width': 1440, 'height': 1000})
            page = context.new_page()
            page.set_default_timeout(15000)
            errors = []
            page.on('pageerror', lambda error: errors.append({'message': str(error), 'stack': error.stack}))
            try:
                page.goto(fixture.address + '/', wait_until='domcontentloaded')
                expect(page.get_by_role('button', name='新建对话', exact=True)).to_be_visible(timeout=20000)
                image_boundaries(page, fixture, artifacts)
                assert not errors, errors
                assert not fixture.call('/status')['failures'], fixture.call('/status')['failures']
                print(json.dumps({'result': 'passed', 'chromium': browser.version}))
            # DEFENSE: Browser/service failures and user cancellation must preserve diagnostics before rethrowing the original failure.
            except BaseException as failure:
                driver.capture_failure(page, fixture, artifacts, errors, failure)
                raise
            finally:
                context.close()
                browser.close()
    finally:
        fixture.close()


if __name__ == '__main__':
    main()
