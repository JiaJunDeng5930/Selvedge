#!/usr/bin/env python3
"""Search real conversations and open an old message in Chromium.

Run after the production build with Python Playwright and CHROMIUM_BIN available:
  BUN_BIN=bun python3 scripts/test-history-search-browser.py
"""
import argparse
import json
import os
from pathlib import Path
import runpy
import shutil
import tempfile
from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1]
SUPPORT = runpy.run_path(str(ROOT / 'scripts/test-interactive-markdown-browser.py'))
Fixture = SUPPORT['Fixture']
capture_failure = SUPPORT['capture_failure']


def seed(fixture, workspace):
    projects = []
    for name in ['Search Alpha Project', 'Search Beta Project']:
        root = Path(workspace) / name
        root.mkdir()
        projects.append(fixture.command(op='create_project', name=name, workspace={'roots': [str(root)]})['project_id'])
    work_a = fixture.command(op='create_work', name='Search First Work')['work_id']
    work_b = fixture.command(op='create_work', name='Search Second Work')['work_id']
    marker = 'Original source: 星河 Needle exact assistant message.'
    sources = []
    for title, project, work in [('Search original conversation', projects[0], work_a),
                                 ('Search other project', projects[1], work_a),
                                 ('Search other Work', projects[0], work_b)]:
        created = fixture.command(op='create_work_task', work_id=work, profile='interactive',
                                  settings={'project_id': project}, message=title)
        request = fixture.request(title)
        text = marker if not sources else title + ': 星河 Needle another match.'
        fixture.finish(request, text=text + '\n\nThe nearby sentence preserves the original discussion.')
        page = fixture.idle(created['task_id'])
        index = next(index for index, message in enumerate(page['messages'])
                     if message.get('role') == 'model_context' and message['content']['type'] == 'provider_receipt'
                     and message['content']['item']['role'] == 'assistant'
                     and message['content']['item']['content'][0]['text'].startswith(text))
        sources.append({'task_id': created['task_id'], 'title': page['task']['title'], 'message_index': index})
    target = sources[0]
    later = 'Continue this conversation with a long later response.'
    fixture.command(op='send', task_id=target['task_id'], message=later)
    request = fixture.request(later)
    fixture.finish(request, text='\n\n'.join('Later paragraph ' + str(index) + ': ' + ('Ordinary later conversation. ' * 12)
                                               for index in range(65)))
    fixture.idle(target['task_id'])
    return target, sources, marker


def search(page, enter=False):
    page.get_by_label('关键词', exact=True).filter(visible=True).fill('星河 Needle')
    if enter:
        page.get_by_label('关键词', exact=True).filter(visible=True).press('Enter')
    else:
        page.get_by_role('button', name='搜索', exact=True).filter(visible=True).click()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--chromium', default=os.environ.get('CHROMIUM_BIN') or shutil.which('chromium'))
    parser.add_argument('--artifacts', default=str(ROOT / '.workpad/history-search-browser-results'))
    args = parser.parse_args()
    # DEFENSE: The physical browser check needs an installed Chromium executable.
    if not args.chromium:
        raise RuntimeError('Chromium is required; set CHROMIUM_BIN')
    artifacts = Path(args.artifacts)
    artifacts.mkdir(parents=True, exist_ok=True)
    screenshots = ROOT / '.workpad/conversation-search'
    screenshots.mkdir(parents=True, exist_ok=True)
    workspace = tempfile.TemporaryDirectory(prefix='selvedge-search-browser-')
    fixture = Fixture()
    try:
        target, sources, marker = seed(fixture, workspace.name)
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(executable_path=args.chromium, headless=True, args=['--no-sandbox'])
            context = browser.new_context(viewport={'width': 1440, 'height': 1000})
            page = context.new_page()
            page.set_default_timeout(20000)
            errors = []
            page.on('pageerror', lambda error: errors.append({'message': str(error), 'stack': error.stack}))
            try:
                page.goto(fixture.address + '/', wait_until='domcontentloaded')
                page.get_by_role('button', name='搜索对话', exact=True).filter(visible=True).click()
                search(page, enter=True)
                for source in sources:
                    name = source['title'] + ' · 消息 #' + str(source['message_index'] + 1)
                    expect(page.get_by_role('button', name=name, exact=True).filter(visible=True)).to_be_visible()
                page.get_by_role('combobox', name='项目', exact=True).filter(visible=True).select_option(label='Search Alpha Project')
                page.get_by_role('combobox', name='Work', exact=True).filter(visible=True).select_option(label='Search First Work')
                search(page)
                name = target['title'] + ' · 消息 #' + str(target['message_index'] + 1)
                result = page.get_by_role('button', name=name, exact=True).filter(visible=True)
                expect(result).to_be_visible()
                for source in sources[1:]:
                    other = source['title'] + ' · 消息 #' + str(source['message_index'] + 1)
                    expect(page.get_by_role('button', name=other, exact=True).filter(visible=True)).to_have_count(0)
                page.screenshot(path=str(screenshots / 'search-results.png'), full_page=False)
                result.click()
                anchor = page.locator('[data-reading-root][data-task-id="' + str(target['task_id']) +
                                      '"] [data-reading-anchor][data-logical-key="message/' +
                                      str(target['message_index']) + '"]').filter(visible=True)
                expect(anchor).to_contain_text(marker)
                expect(anchor).to_be_in_viewport(ratio=.25)
                page.screenshot(path=str(screenshots / 'original-message.png'), full_page=False)
                continuation = 'Continue after locating the original message.'
                fixture.command(op='send', task_id=target['task_id'], message=continuation)
                request = fixture.request(continuation)
                streamed = 'New live response while reading the original message. ' * 80
                fixture.emit(request, streamed)
                page.wait_for_function('''text => Array.from(document.querySelectorAll('[data-reading-root]'))
                  .some(node => !node.closest('[inert]') && node.textContent.includes(text))''',
                                       arg=streamed[:100])
                expect(anchor).to_be_in_viewport(ratio=.25)
                fixture.finish(request, text=streamed)
                fixture.idle(target['task_id'])
                expect(anchor).to_be_in_viewport(ratio=.25)
                assert not errors, errors
                assert not fixture.call('/status')['failures'], fixture.call('/status')['failures']
                page.screenshot(path=str(artifacts / 'located-message.png'), full_page=False)
                print(json.dumps({'result': 'passed', 'boundary': 'global and Project/Work search opens the original old message',
                                  'task_id': target['task_id'], 'message_index': target['message_index'],
                                  'chromium': browser.version}))
            # DEFENSE: Preserve the actual browser/service evidence when the physical search or scroll boundary fails.
            except BaseException as failure:
                capture_failure(page, fixture, artifacts, errors, failure)
                raise
            finally:
                context.close()
                browser.close()
    finally:
        fixture.close()
        workspace.cleanup()


if __name__ == '__main__':
    main()
