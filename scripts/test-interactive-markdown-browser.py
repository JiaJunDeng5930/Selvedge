#!/usr/bin/env python3
"""Real Chromium boundaries for the production interactive Markdown runtime.

Requires Python Playwright and Chromium. Run after `bun run build`:
  BUN_BIN=bun python3 scripts/test-interactive-markdown-browser.py --mode all
No DOM shim, product module replacement, or production test endpoint is installed.
The duplicate-action scenario defers a real command response at the network
boundary and releases it through the actual service.
"""
import argparse
import json
import os
import re
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
from urllib.request import Request, urlopen
from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1]


def capture_failure(page, fixture, artifacts, errors, failure):
    """Preserve the original failure even if the renderer cannot produce a screenshot."""
    (artifacts / 'failure.txt').write_text(''.join(traceback.format_exception(failure)))
    (artifacts / 'page-errors.json').write_text(json.dumps(errors, indent=2))
    capture_errors = []
    try:
        stored = page.wait_for_function('''()=>{
          const entries={};
          for(let index=0;index<localStorage.length;index++) {
            const key=localStorage.key(index);
            if(key?.startsWith('selvedge-interactive-v1/'))entries[key]=localStorage.getItem(key);
          }
          return JSON.stringify(entries);
        }''', timeout=2000)
        try:
            (artifacts / 'interactive-storage.json').write_text(stored.json_value())
        finally:
            stored.dispose()
    # DEFENSE: A failed renderer or detached browser can reject storage inspection; retain that capture error beside the original test failure.
    except Exception as error:
        capture_errors.append('interactive storage: ' + str(error))
    try:
        (artifacts / 'fixture-status.json').write_text(json.dumps(fixture.call('/status'), indent=2))
    # DEFENSE: A service failure can make its diagnostic HTTP endpoint unavailable; preserve the original browser-test failure.
    except Exception as error:
        capture_errors.append('fixture status: ' + str(error))
    try:
        page.screenshot(path=str(artifacts / 'failure.png'), full_page=True, timeout=5000)
    # DEFENSE: A crashed or disconnected Chromium renderer cannot produce a screenshot; record that diagnostic failure.
    except Exception as error:
        capture_errors.append('screenshot: ' + str(error))
    else:
        try:
            (artifacts / 'failure.html').write_text(page.content())
        # DEFENSE: Chromium can disconnect after a screenshot but before HTML capture; record the missing diagnostic.
        except Exception as error:
            capture_errors.append('page content: ' + str(error))
    if capture_errors:
        (artifacts / 'capture-errors.json').write_text(json.dumps(capture_errors, indent=2))


class Fixture:
    def __init__(self):
        bun = os.environ.get('BUN_BIN') or shutil.which('bun')
        # DEFENSE: A developer machine can lack the Bun executable needed by the real service fixture.
        if not bun:
            raise RuntimeError('Bun is required; set BUN_BIN to the installed binary')
        self.log = tempfile.TemporaryFile(mode='w+')
        self.proc = None
        try:
            self.proc = subprocess.Popen([bun, 'tests-bend/fixtures/interactive-markdown.mjs'], cwd=ROOT,
                                         stdout=subprocess.PIPE, stderr=self.log, text=True)
            # DEFENSE: A failed or stalled service subprocess may never publish its loopback address.
            if not select.select([self.proc.stdout], [], [], 30)[0]:
                raise RuntimeError('Production fixture did not start within 30 seconds')
            line = self.proc.stdout.readline()
            # DEFENSE: A service startup failure closes stdout before publishing the fixture address.
            if not line:
                self.log.seek(0)
                raise RuntimeError('Production fixture failed to start: ' + self.log.read())
            self.info = json.loads(line)
            self.address = self.info['address']
            self.control = self.info['control']
        # DEFENSE: Process creation, startup parsing or user cancellation can interrupt construction after the log or subprocess was allocated.
        except BaseException:
            self.close()
            raise

    def call(self, route, value=None):
        request = Request(self.control + route,
                          data=None if value is None else json.dumps(value).encode(),
                          headers={'content-type': 'application/json'})
        with urlopen(request, timeout=30) as response:
            result = json.load(response)
        # DEFENSE: The control HTTP peer reports failed restart/request operations as an explicit JSON error.
        if 'error' in result:
            raise AssertionError(result)
        return result

    def command(self, **value):
        result = self.call('/command', value)
        assert result['reply']['ok'], result
        return result['reply']['result']

    def request(self, marker):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            for request in self.call('/status')['requests']:
                if request['closed']:
                    continue
                if marker in json.dumps(request['input'], ensure_ascii=False):
                    return request['index']
            time.sleep(.05)
        # DEFENSE: A service/provider regression can prevent the expected HTTP model request within the fixture deadline.
        raise AssertionError('No actual provider request for ' + marker)

    def emit(self, index, text):
        self.call('/emit', {'index': index, 'text': text})

    def finish(self, index, **value):
        self.call('/finish', {'index': index, **value})

    def idle(self, task):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            value = self.command(op='read', task_id=task)
            if value['task']['phase'] == 'idle' and not value['task']['operations']:
                return value
            time.sleep(.05)
        # DEFENSE: A service/provider regression can leave the task unsettled beyond the fixture deadline.
        raise AssertionError('Task did not become idle: ' + str(task))

    def close(self):
        # DEFENSE: Construction can fail before spawning, or the subprocess can already have exited during a test failure.
        if self.proc is not None and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            # DEFENSE: A failed service shutdown may ignore SIGTERM; kill the owned fixture after its shutdown deadline.
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        self.log.seek(0)
        log = self.log.read()
        self.log.close()
        if log:
            print(log, file=sys.stderr)


def navigate_task_id(page, task_id):
    deadline = time.monotonic() + 15
    identity = page.wait_for_function('''id => {
      for(const button of document.querySelectorAll('button[data-native-key]')) {
        if(button.closest('[inert]'))continue;
        const key=JSON.parse(button.dataset.nativeKey), owner=key[1];
        if(key[0]==='part' && key[2]==='task/'+id && owner[0]==='entity'
            && owner[2]==='task' && owner[3]===String(id))
          return button.dataset.nativeKey;
      }
      return false;
    }''', arg=task_id, timeout=15000)
    try:
        key = identity.json_value()
    finally:
        identity.dispose()
    remaining = max(1, (deadline - time.monotonic()) * 1000)
    page.locator('button[data-native-key=' + json.dumps(key) + ']').filter(visible=True).click(timeout=remaining)
    expect(page.get_by_role('button', name='Task details', exact=True)).to_be_visible()
    expect(page.locator('textarea[data-object-owner="message-draft/' + str(task_id) + '"][data-field="message-text"]').filter(visible=True)).to_be_visible()


def document_contains_marker(page, marker):
    return page.evaluate('''marker => document.documentElement.textContent.includes(marker) ||
      Array.from(document.querySelectorAll('input,textarea,[aria-label],[title]')).some(node=>
        [node.value,node.getAttribute('aria-label'),node.getAttribute('title')]
          .some(value=>typeof value==='string'&&value.includes(marker)))''', marker)


def no_document_marker(page, marker):
    page.wait_for_function('''marker => !document.documentElement.textContent.includes(marker) &&
      !Array.from(document.querySelectorAll('input,textarea,[aria-label],[title]')).some(node=>
        [node.value,node.getAttribute('aria-label'),node.getAttribute('title')]
          .some(value=>typeof value==='string'&&value.includes(marker)))''', arg=marker)
    page.evaluate('''async()=>{await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));}''')
    assert not document_contains_marker(page, marker), 'A retired physical probe republished private content: ' + marker


def saved_values(page, ui_id, expected):
    page.wait_for_function('''({ui,expected}) => Object.entries(localStorage).some(([key,raw])=>{
      if(!key.startsWith('selvedge-interactive-v1/'))return false;
      // DEFENSE: User-editable localStorage can contain malformed JSON under the current namespace; ignore only the malformed entry.
      try {
        const snapshot=JSON.parse(raw);
        if(!snapshot.definition.includes('<ui id="'+ui+'"'))return false;
        const values=Object.fromEntries(snapshot.payload.locals.map(local=>[local.id,local.value]));
        return Object.entries(expected).every(([name,value])=>values[name]===value);
      }catch(error){if(error instanceof SyntaxError)return false;throw error;}
    })''', arg={'ui': ui_id, 'expected': expected})


def calculator_boundaries(page, fixture):
    title = 'Interactive calculator browser fixture'
    created = fixture.command(op='create', profile='interactive', message=title)
    request = fixture.request(title)
    navigate_task_id(page, created['task_id'])
    prefix = '''## Calculator

```selvedge-ui
<ui id="calculator">
<state id="seats" type="integer" initial={8} min={1} max={50} />
<state id="note" type="string" initial="" max-length={1000} />
<derive id="monthly" value={seats * 29} />
<stack id="layout" gap="md">
<text id="namespace-marker" label="Private calculator namespace marker" />
<slider id="seat-slider" bind="seats" label="Seats" />
<metric id="price" label="Monthly price" value={monthly} format="currency:USD" />
<text-input id="note-input" bind="note" label="Note" />
<text id="note-echo" label={"Note echo: " + note} />
<text id="tail" label="'''
    fixture.emit(request, prefix)
    slider = page.get_by_role('slider', name='Seats', exact=True)
    expect(slider).to_be_visible(timeout=20000)
    expect(slider).to_have_value('8')
    slider_handle = slider.element_handle()
    slider.focus()
    slider.press('ArrowRight')
    expect(slider).to_have_value('9')
    expect(page.get_by_text('$261.00', exact=True).filter(visible=True)).to_be_visible()
    note = page.get_by_role('textbox', name='Note', exact=True).filter(visible=True)
    note.focus()
    note_handle = note.element_handle()
    cdp = page.context.new_cdp_session(page)
    cdp.send('Input.imeSetComposition', {'text': '中文输入', 'selectionStart': 4, 'selectionEnd': 4})
    suffix = 'Tail accepted" />\n</stack>\n</ui>\n```\n\nAfter the interactive block.\n'
    fixture.emit(request, suffix)
    expect(page.get_by_text('Tail accepted', exact=True).filter(visible=True)).to_be_visible()
    assert note.evaluate('(node,old)=>node===old', note_handle), 'stream append replaced composing input'
    expect(note).to_have_value('中文输入')
    cdp.send('Input.insertText', {'text': '中文输入'})
    fixture.finish(request)
    fixture.idle(created['task_id'])
    saved_values(page, 'calculator', {'seats': 9, 'note': '中文输入'})
    assert slider.evaluate('(node,old)=>node===old', slider_handle), 'completion replaced the live slider'
    assert note.evaluate('(node,old)=>node===old', note_handle), 'completion replaced composing input'
    expect(slider).to_have_value('9')
    expect(note).to_have_value('中文输入')
    expect(page.get_by_text('After the interactive block.', exact=True).filter(visible=True)).to_be_visible()
    page.reload(wait_until='domcontentloaded')
    navigate_task_id(page, created['task_id'])
    expect(page.get_by_role('slider', name='Seats', exact=True)).to_have_value('9', timeout=20000)
    expect(page.get_by_role('textbox', name='Note', exact=True).filter(visible=True)).to_have_value('中文输入')
    print(json.dumps({'boundary': 'actual provider streaming → committed controls, native slider/IME and reload restoration', 'passed': True}))
    return created['task_id']


def plain_source_boundaries(page, fixture, task):
    marker = 'Plain user source browser fixture'
    fixture.command(op='send', task_id=task, message=marker + '''
```selvedge-ui
<ui id="user-code"><button id="user-button" label="User code must remain literal" action="reset" /></ui>
```
''')
    request = fixture.request(marker)
    fixture.finish(request, text='The user-provided code remains ordinary Markdown.')
    fixture.idle(task)
    expect(page.get_by_role('button', name='User code must remain literal', exact=True)).to_have_count(0)
    expect(page.locator('code').filter(has_text='User code must remain literal').filter(visible=True)).to_be_visible()
    expect(page.get_by_role('slider', name='Seats', exact=True)).to_have_value('9')
    code = page.locator('code').filter(has_text='User code must remain literal').filter(visible=True)
    literal = '<ui id="user-code"><button id="user-button" label="User code must remain literal" action="reset" /></ui>'
    assert code.text_content() in [literal, literal + '\n'], 'The ordinary code lost or changed source characters'
    code.evaluate('''async code => {
      await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
      const pre=code.closest('pre');
      const block=pre?.parentElement;
      const allocation=code.closest('.physical-markdown');
      if(!pre||!block||!allocation)throw Error('Ordinary code has no allocated scroll viewport');
      if(pre.clientWidth<=0||pre.getBoundingClientRect().width>allocation.getBoundingClientRect().width+1)
        throw Error('Ordinary code escaped its allocated content box');
      if(pre.scrollWidth<=pre.clientWidth)throw Error('The intact long code line has no horizontal scroll extent');
      const original=pre.scrollLeft;
      try {
        pre.scrollLeft=0;
        pre.scrollLeft=Math.min(37,pre.scrollWidth-pre.clientWidth);
        if(pre.scrollLeft<=0)throw Error('The long code line cannot scroll horizontally');
      } finally {pre.scrollLeft=original;}
    }''')
    expect(page.get_by_role('slider', name='Seats', exact=True)).to_have_value('9')
    expect(page.get_by_role('button', name='User code must remain literal', exact=True)).to_have_count(0)
    print(json.dumps({'boundary': 'exact UI fences from plain user messages stay literal while earlier assistant UI retains input', 'passed': True}))


def graph_boundaries(page, fixture):
    worker_title = 'Live graph worker browser fixture'
    graph = fixture.command(op='create_task_graph', name='Live graph browser fixture',
                            nodes=[{'key': 'alpha', 'profile': 'interactive', 'message': worker_title}], rules=[])
    worker = graph['nodes'][0]['task_id']
    worker_request = fixture.request(worker_title)
    monitor_title = 'Live graph monitor browser fixture'
    monitor = fixture.command(op='create', profile='interactive', message=monitor_title)['task_id']
    monitor_request = fixture.request(monitor_title)
    code = '''```selvedge-ui
<ui id="monitor">
<source id="workflow" kind="task-graph" graph-id={GRAPH_ID} mode="live" />
<text id="freshness" label={"Fresh: " + text(workflow.fresh)} />
<resource-view id="resource" source="workflow" let="graph">
<graph-view id="diagram" nodes={graph.nodes} edges={graph.edges} node-key="identity" layout="stable">
<node-template item="node">
<stack id="node-layout">
<task-node id="task" label={node.key} task={node.task} />
<text id="working" label={"Working: " + text(working(node.task))} />
</stack>
</node-template>
</graph-view>
</resource-view>
</ui>
```
'''.replace('GRAPH_ID', str(graph['graph_id']))
    fixture.emit(monitor_request, code)
    fixture.finish(monitor_request)
    navigate_task_id(page, monitor)
    expect(page.get_by_text('Working: true', exact=True).filter(visible=True)).to_be_visible(timeout=20000)
    page.context.set_offline(True)
    fixture.call('/disconnect', {})
    expect(page.get_by_text('Fresh: false', exact=True).filter(visible=True)).to_be_visible(timeout=20000)
    fixture.finish(worker_request, text='Graph worker completed.')
    fixture.idle(worker)
    page.context.set_offline(False)
    expect(page.get_by_text('Fresh: true', exact=True).filter(visible=True)).to_be_visible(timeout=20000)
    expect(page.get_by_text('Working: false', exact=True).filter(visible=True)).to_be_visible()
    print(json.dumps({'boundary': 'real task graph state display, offline freshness and reconnect', 'passed': True}))


def action_boundaries(page, fixture):
    title = 'Explicit action browser fixture'
    task = fixture.command(op='create', profile='interactive', message=title)['task_id']
    request = fixture.request(title)
    code = '''```selvedge-ui
<ui id="actions">
<button id="send" label="Send chosen count" action="submit" message="Chosen count: 2" />
<button id="send-again" label="Send same count" action="submit" message="Chosen count: 2" />
</ui>
```
'''
    fixture.emit(request, code)
    fixture.finish(request)
    fixture.idle(task)
    navigate_task_id(page, task)
    composer = page.get_by_role('textbox', name='Message', exact=True).filter(visible=True)
    expect(composer).to_have_attribute('data-object-owner', f'message-draft/{task}')
    composer.click()
    composer.fill('Preserve this user draft')
    before = len(fixture.call('/status')['requests'])
    held_commands = []
    def hold_submit(route):
        held_commands.append(route)
    page.route('**/api/browser/command', hold_submit)
    submit = page.get_by_role('button', name='Send chosen count', exact=True).filter(visible=True)
    duplicate = page.get_by_role('button', name='Send same count', exact=True).filter(visible=True)
    try:
        submit.click()
        expect(submit).to_be_disabled()
        duplicate.click()
        expect(page.get_by_text('This command is already pending', exact=True).filter(visible=True)).to_be_visible()
        expect(duplicate).to_be_enabled()
        expect(submit).to_be_disabled()
        assert len(held_commands) == 1, 'A duplicate button emitted another command'
        response = held_commands[0].fetch()
        assert response.ok
        held_commands[0].fulfill(response=response)
    finally:
        page.unroute('**/api/browser/command', hold_submit)
    reply = fixture.request('Chosen count: 2')
    expect(composer).to_have_value('Preserve this user draft')
    assert len(fixture.call('/status')['requests']) == before + 1
    fixture.finish(reply, text='Explicit submission accepted once.')
    messages = fixture.idle(task)['messages']
    expect(submit).to_be_enabled(timeout=20000)
    expect(duplicate).to_be_enabled()
    assert len([message for message in messages if message.get('role') == 'user' and message.get('content') == 'Chosen count: 2']) == 1
    print(json.dumps({'boundary': 'correlated submit: duplicate intent settles without a second command or a stuck button', 'passed': True}))


def namespace_boundaries(page, fixture, parent):
    old_namespace = page.evaluate("async()=> (await (await fetch('/api/browser/state')).json()).namespace")
    old_text = next(request['text'] for request in fixture.call('/status')['requests']
                    if 'Interactive calculator browser fixture' in json.dumps(request['input']) and '<ui id="calculator">' in request['text'])
    navigate_task_id(page, parent)
    restarted = fixture.call('/restart', {})
    assert restarted['address'] == fixture.address, 'A restart must preserve the browser storage origin'
    page.evaluate("async()=>{if(!(await fetch('/')).ok)throw Error('Could not refresh the real session cookie');}")
    assert page.evaluate("async()=> (await (await fetch('/api/browser/state')).json()).namespace") == old_namespace
    expect(page.get_by_role('slider', name='Seats', exact=True)).to_have_value('9', timeout=20000)
    page.set_viewport_size({'width': 900, 'height': 800})
    page.wait_for_function('''() => Array.from(document.querySelectorAll('body > [aria-hidden="true"][inert]'))
      .some(root=>root.textContent.includes('Private calculator namespace marker'))''')
    restarted = fixture.call('/restart', {'differentNamespace': True})
    assert restarted['address'] == fixture.address
    page.evaluate("async()=>{if(!(await fetch('/')).ok)throw Error('Could not refresh the real session cookie');}")
    assert page.evaluate("async()=> (await (await fetch('/api/browser/state')).json()).namespace") != old_namespace
    no_document_marker(page, 'Private calculator namespace marker')
    page.set_viewport_size({'width': 1440, 'height': 1000})
    title = 'New namespace calculator browser fixture'
    task = fixture.command(op='create', profile='interactive', message=title)['task_id']
    request = fixture.request(title)
    fixture.emit(request, old_text)
    fixture.finish(request)
    navigate_task_id(page, task)
    expect(page.get_by_role('slider', name='Seats', exact=True)).to_have_value('8', timeout=20000)
    expect(page.get_by_role('textbox', name='Note', exact=True).filter(visible=True)).to_have_value('')
    print(json.dumps({'boundary': 'same-journal restart restoration and different-journal namespace isolation', 'passed': True}))


def authorization_boundaries(page, fixture):
    graph = fixture.command(op='create_task_graph', name='Revocation source graph',
                            nodes=[{'key': 'private', 'profile': 'demo', 'message': 'Revocation source worker'}], rules=[])
    fixture.idle(graph['nodes'][0]['task_id'])
    title = 'Revocation monitor browser fixture'
    task = fixture.command(op='create', profile='interactive', message=title)['task_id']
    request = fixture.request(title)
    fixture.emit(request, '''```selvedge-ui
<ui id="revocation">
<source id="workflow" kind="task-graph" graph-id={GRAPH_ID} mode="live" />
<resource-view id="resource" source="workflow" let="graph">
<graph-view id="diagram" nodes={graph.nodes} edges={graph.edges} node-key="identity" layout="stable">
<node-template item="node"><stack id="node-content">
<text id="private-projection" label={"Revoked projection: " + node.identity} />
<task-node id="task" task={node.task} label={node.key} />
</stack></node-template>
</graph-view>
</resource-view>
</ui>
```
'''.replace('GRAPH_ID', str(graph['graph_id'])))
    fixture.finish(request)
    navigate_task_id(page, task)
    projection = page.get_by_text(re.compile('^Revoked projection: ')).filter(visible=True)
    expect(projection).to_be_visible(timeout=20000)
    marker = projection.inner_text()
    page.set_viewport_size({'width': 900, 'height': 800})
    page.wait_for_function('''marker => Array.from(document.querySelectorAll('body > [aria-hidden="true"][inert]'))
      .some(root=>root.textContent.includes(marker))''', arg=marker)
    page.context.set_extra_http_headers({'Origin': 'http://untrusted.invalid'})
    with page.expect_response(lambda response: '/api/browser/state' in response.url and response.status == 403):
        fixture.command(op='create', profile='demo', message='Trigger a real forbidden snapshot refresh')
    no_document_marker(page, marker)
    page.context.set_extra_http_headers({})
    fixture.call('/disconnect', {})
    expect(projection).to_be_visible(timeout=20000)
    page.set_viewport_size({'width': 1440, 'height': 1000})
    print(json.dumps({'boundary': 'actual HTTP 403 revokes live source projections from visible and inert measurement DOM, then reauthorizes', 'passed': True}))


def side_conversation_boundaries(page, fixture, artifacts):
    title = 'Concurrent side conversation browser fixture'
    parent = fixture.command(op='create', profile='interactive', message=title)['task_id']
    parent_request = fixture.request(title)
    navigate_task_id(page, parent)
    composer = page.get_by_role('textbox', name='Message', exact=True).filter(visible=True)
    composer.fill('/side')
    composer.press('Enter')
    expect(page.get_by_text(re.compile(r'^Side conversation · task #')).filter(visible=True)).to_be_visible()
    tasks = fixture.command(op='list')['tasks']
    side = next(task['id'] for task in tasks if task['parent'] == parent)
    assert not fixture.call('/status')['requests'][parent_request]['closed'], 'Opening a side cancelled the parent request'
    composers = page.get_by_role('textbox', name='Message', exact=True).filter(visible=True)
    expect(composers).to_have_count(2)
    side_composer = composers.last
    side_composer.fill('Inspect the parent before reflecting on its approach.')
    side_composer.press('Enter')
    side_request = fixture.request('Inspect the parent before reflecting')
    side_input = fixture.call('/status')['requests'][side_request]['input']
    assert 'Its parent is task #' + str(parent) in json.dumps(side_input)
    fixture.finish(side_request, output=[{'type': 'function_call', 'call_id': 'inspect-parent',
                                        'name': 'read_task', 'arguments': json.dumps({'task_id': parent})}])
    side_reply = fixture.request('inspect-parent')
    assert 'model_pending' in json.dumps(fixture.call('/status')['requests'][side_reply]['input'])
    fixture.emit(parent_request, 'The parent keeps streaming while the side conversation is open.\n')
    expect(page.get_by_text('The parent keeps streaming while the side conversation is open.', exact=True).filter(visible=True)).to_be_visible()
    fixture.finish(side_reply, text='''Side reflection with a local note.

```selvedge-ui
<ui id="side-note">
<state id="note" type="string" initial="" />
<text-input id="note-input" label="Side note" bind="note" />
</ui>
```
''')
    fixture.idle(side)
    note = page.get_by_role('textbox', name='Side note', exact=True).filter(visible=True)
    expect(note).to_be_visible()
    parent_box, side_box = composers.first.bounding_box(), composers.last.bounding_box()
    assert side_box['x'] >= parent_box['x'] + parent_box['width'], 'Desktop side conversation is not beside its parent'
    assert page.viewport_size['height'] - 200 <= side_box['y'] < page.viewport_size['height'], 'Side composer is not docked at the bottom'
    page.screenshot(path=str(artifacts / 'side-desktop.png'))
    note.focus()
    cdp = page.context.new_cdp_session(page)
    cdp.send('Input.imeSetComposition', {'text': '侧聊', 'selectionStart': 2, 'selectionEnd': 2})
    fixture.emit(parent_request, 'Another parent stream update during side input.\n')
    expect(note).to_have_value('侧聊')
    cdp.send('Input.insertText', {'text': '侧聊'})
    page.set_viewport_size({'width': 650, 'height': 900})
    expect(page.get_by_role('dialog').filter(visible=True)).to_be_visible()
    expect(page.get_by_role('textbox', name='Side note', exact=True).filter(visible=True)).to_have_value('侧聊')
    page.screenshot(path=str(artifacts / 'side-mobile.png'))
    page.set_viewport_size({'width': 1440, 'height': 1000})
    page.get_by_role('button', name='关闭', exact=True).filter(visible=True).click()
    expect(page.get_by_role('textbox', name='Message', exact=True).filter(visible=True)).to_have_count(1)
    assert fixture.command(op='read', task_id=parent)['task']['queued'] == 0, 'Closing a side returned content'
    assert not fixture.call('/status')['requests'][parent_request]['closed']
    navigate_task_id(page, side)
    page.get_by_role('button', name='追加回 task #' + str(parent), exact=True).filter(visible=True).click()
    deadline = time.monotonic() + 15
    while fixture.command(op='read', task_id=parent)['task']['queued'] != 1:
        assert time.monotonic() < deadline, 'Manual return did not reach the running parent queue'
        page.wait_for_timeout(50)
    assert not fixture.call('/status')['requests'][parent_request]['closed'], 'Returning side content cancelled parent inference'
    fixture.finish(parent_request)
    returned_request = fixture.request('Side reflection with a local note.')
    returned_input = fixture.call('/status')['requests'][returned_request]['input']['input']
    transfer = next(item['content'] for item in returned_input
                    if item.get('role') == 'user' and 'Side reflection with a local note.' in str(item.get('content')))
    assert 'inspect-parent' in transfer, 'Return lost the new tool conversation'
    for administrative in ['side_conversation', 'side_return_cursor', 'task_lifecycle', 'Its parent is task #']:
        assert administrative not in transfer, 'Side runtime context leaked into returned content: ' + administrative
    fixture.finish(returned_request, text='Parent received the side reflection.')
    fixture.idle(parent)
    assert any('task_lifecycle' in json.dumps(message) and message.get('change', {}).get('type') == 'amend'
               for message in fixture.command(op='read', task_id=side)['messages'])
    navigate_task_id(page, parent)
    held_commands = []
    def hold_side_creation(route):
        if route.request.post_data_json['command']['op'] == 'open_side_conversation':
            held_commands.append(route)
        else:
            route.continue_()
    page.route('**/api/browser/command', hold_side_creation)
    try:
        composer = page.get_by_role('textbox', name='Message', exact=True).filter(visible=True)
        composer.fill('/side')
        composer.press('Enter')
        deadline = time.monotonic() + 15
        while not held_commands:
            assert time.monotonic() < deadline, 'No side creation crossed the browser command boundary'
            page.wait_for_timeout(50)
        navigate_task_id(page, side)
        response = held_commands[0].fetch()
        assert response.ok
        held_commands[0].fulfill(response=response)
    finally:
        page.unroute('**/api/browser/command', hold_side_creation)
    expect(page.get_by_role('textbox', name='Message', exact=True).filter(visible=True)).to_have_count(1)
    navigate_task_id(page, parent)
    expect(page.get_by_role('textbox', name='Message', exact=True).filter(visible=True)).to_have_value('')
    fixture.call('/restart', {})
    before = fixture.command(op='read', task_id=parent)['cursor']
    replayed = fixture.call('/command', {'op': 'return_side_conversation', 'task_id': side})
    assert not replayed['reply']['ok'] and replayed['reply']['error']['code'] == 'no_side_content', replayed
    assert fixture.command(op='read', task_id=parent)['cursor'] == before
    print(json.dumps({'boundary': 'concurrent provider streams, side input/IME, explicit filtered return and durable cursor replay', 'passed': True}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['calculator', 'graph', 'actions', 'namespace', 'authorization', 'side', 'all'], default='all')
    parser.add_argument('--chromium', default=os.environ.get('CHROMIUM_BIN') or shutil.which('chromium'))
    parser.add_argument('--artifacts', default=str(ROOT / '.workpad/interactive-browser-results'))
    args = parser.parse_args()
    # DEFENSE: A developer machine can lack Chromium, which this physical browser regression requires.
    if not args.chromium:
        raise RuntimeError('Chromium is required; set CHROMIUM_BIN')
    artifacts = Path(args.artifacts)
    artifacts.mkdir(parents=True, exist_ok=True)
    fixture = Fixture()
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
                if args.mode in ['calculator', 'namespace', 'all']:
                    parent = calculator_boundaries(page, fixture)
                if args.mode == 'all':
                    plain_source_boundaries(page, fixture, parent)
                if args.mode in ['graph', 'all']:
                    graph_boundaries(page, fixture)
                if args.mode in ['actions', 'all']:
                    action_boundaries(page, fixture)
                if args.mode in ['namespace', 'all']:
                    namespace_boundaries(page, fixture, parent)
                if args.mode in ['authorization', 'all']:
                    authorization_boundaries(page, fixture)
                if args.mode in ['side', 'all']:
                    side_conversation_boundaries(page, fixture, artifacts)
                assert not errors, errors
                assert not fixture.call('/status')['failures'], fixture.call('/status')['failures']
                print(json.dumps({'result': 'passed', 'mode': args.mode, 'chromium': browser.version}))
            # DEFENSE: Browser/service failures and user cancellation must save available diagnostics before rethrowing the original failure.
            except BaseException as failure:
                capture_failure(page, fixture, artifacts, errors, failure)
                raise
            finally:
                context.close()
                browser.close()
    finally:
        fixture.close()


if __name__ == '__main__':
    main()
