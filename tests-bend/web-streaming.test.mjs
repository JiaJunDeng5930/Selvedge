import test from 'node:test';
import assert from 'node:assert/strict';
import { PacedText, safeHref } from '../host/public/markdown.mjs';
import { EventFrames, acknowledgeDrafts } from '../host/public/events.mjs';
import { Streams } from '../host/public/streams.mjs';

function clock() {
  let id = 0;
  let time = 0;
  const jobs = new Map();
  return {
    frame: callback => { jobs.set(++id, callback); return id; },
    cancel: key => jobs.delete(key),
    tick: () => { time += 16; const queued = [...jobs.values()]; jobs.clear(); for (const job of queued) job(time); },
    get size() { return jobs.size; },
  };
}

test('target arrivals coalesce, visible batches are bounded, and no previous prefix is reprocessed', () => {
  const scheduling = clock();
  const chunks = [];
  let ended = 0;
  const output = new PacedText(chunk => chunks.push(chunk), () => ended++, scheduling);
  const text = 'A stable paragraph.\n\n'.repeat(15000);
  for (const char of text) output.append(char);
  assert.equal(chunks.length, 0, 'arrivals never trigger parsing');
  assert.equal(scheduling.size, 1, 'there is only one scheduled display update');
  scheduling.tick();
  const first = chunks.length;
  scheduling.tick();
  assert.equal(chunks.length, first, '16ms input timing cannot force a 60Hz parse');
  output.finish();
  for (let i = 0; scheduling.size && i < 1000; i++) scheduling.tick();
  assert.equal(ended, 1);
  assert.equal(chunks.join(''), text);
  assert.equal(output.metrics.characters, text.length);
  assert.ok(output.metrics.largestBatch <= 4096);
  assert.ok(output.metrics.batches < 150);
  output.append('late'); scheduling.tick(); assert.equal(ended, 1);
});

test('display cancellation and surrogate boundaries do not leak incomplete characters', () => {
  const scheduling = clock();
  const chunks = [];
  const output = new PacedText(chunk => chunks.push(chunk), () => {}, scheduling);
  output.append('hello \ud83d'); scheduling.tick();
  assert.deepEqual(chunks, ['hello ']);
  output.append('\ude03 world'); output.finish();
  for (let i = 0; i < 10; i++) scheduling.tick();
  assert.equal(chunks.join(''), 'hello 😃 world');
  assert.ok(chunks.every(chunk => chunk.isWellFormed()));
  const stopped = new PacedText(() => assert.fail('disposed text rendered'), () => assert.fail('disposed text completed'), scheduling);
  stopped.append('discard'); stopped.dispose(); scheduling.tick();
  assert.equal(scheduling.size, 0);
});

test('links reject active schemes, obfuscated schemes, network-path and relative destinations', () => {
  for (const text of ['javascript:alert(1)', 'java\nscript:alert(1)', 'data:text/html,hello', '//example.com', '/api/commands', '\\example.com', 'file:///etc/passwd']) {
    assert.equal(safeHref(text), null);
  }
  assert.equal(safeHref('https://example.com/a?q=1'), 'https://example.com/a?q=1');
  assert.equal(safeHref('mailto:user@example.com'), 'mailto:user@example.com');
  assert.equal(safeHref('#section'), '#section');
});

test('SSE framing survives every CRLF split, bounded frames and multiline data', () => {
  const events = [];
  const decoder = new EventFrames(event => events.push(event));
  const source = ': comment\r\nid: 7\r\ndata: {"type":\r\ndata: "commit","sequence":7}\r\n\r\n';
  for (const char of source) decoder.write(char);
  assert.deepEqual(events, [{ type: 'commit', sequence: 7 }]);
  const bounded = new EventFrames(() => assert.fail('oversized frame accepted'), 10);
  assert.throws(() => bounded.write('data: ' + 'x'.repeat(11)), /large/);
});

test('successful submission clears only its unchanged draft snapshot', () => {
  const drafts = new Map([['/send/message', 'typed while waiting'], ['/send/other', 'sent'], ['/other/message', 'unrelated']]);
  acknowledgeDrafts(drafts, '/send', { message: 'submitted text', other: 'sent' });
  assert.equal(drafts.get('/send/message'), 'typed while waiting');
  assert.equal(drafts.has('/send/other'), false);
  assert.equal(drafts.get('/other/message'), 'unrelated');
});

test('continuous forms retain native-declared parameters, not submitted content or attachments', () => {
  const drafts = new Map([['/create/title', 'submitted'], ['/create/labels', '["later edit"]'], ['/create/attachments', '["file"]']]);
  acknowledgeDrafts(drafts, '/create', { title: 'submitted', priority: 'high', labels: '["saved"]', attachments: '["file"]' }, ['priority', 'labels']);
  assert.deepEqual([...drafts], [['/create/labels', '["later edit"]'], ['/create/priority', 'high']]);
});

test('previews require an observed start and settlement revision; cancellation rejects late deltas', () => {
  const streams = new Streams();
  const notice = (type, rest = {}) => ({ type, task_id: 4, ticket: 9, ...rest });
  streams.receive(notice('delta', { output_index: 0, text: 'unobserved prefix' }));
  assert.equal(streams.sessions.size, 0);
  streams.receive(notice('stream_start'));
  streams.receive(notice('delta', { output_index: 0, text: 'answer' }));
  streams.receive(notice('delta', { output_index: 1, text: 'second item' }));
  assert.equal(streams.sessions.get('4:9').items.size, 2);
  assert.equal(streams.take('answer', 4, 100), null, 'unsettled content is not adopted');
  streams.receive(notice('stream_end', { sequence: 10 }));
  streams.surface(null, 4, 9);
  assert.equal(streams.sessions.size, 1, 'an unrelated earlier commit cannot retire a preview');
  streams.surface(null, 4, 10);
  assert.equal(streams.sessions.size, 0);
  streams.receive(notice('stream_start'));
  streams.receive(notice('stream_cancel'));
  streams.receive(notice('delta', { output_index: 0, text: 'late' }));
  assert.equal(streams.sessions.size, 0);
  assert.equal(streams.characters, 0);
});

test('snapshots replace provisional text, including shrinking and clearing, without changing other output items', () => {
  const streams = new Streams();
  const notice = (type, text = '', index = 0) => ({ type, task_id: 2, ticket: 3, output_index: index, text });
  streams.receive(notice('snapshot', 'unobserved'));
  assert.equal(streams.sessions.size, 0);
  streams.receive(notice('stream_start'));
  streams.receive(notice('snapshot', 'long provisional answer'));
  streams.receive(notice('delta', 'other output', 1));
  const items = streams.sessions.get('2:3').items;
  let disposed = 0;
  let removed = 0;
  let appended = '';
  items.get(0).markdown = { dispose() { disposed++; }, append(text) { appended += text; } };
  items.get(0).container = { remove() { removed++; } };
  streams.receive(notice('snapshot', 'long provisional answer!'));
  assert.equal(appended, '!');
  streams.receive(notice('snapshot', 'short'));
  assert.equal(disposed, 1);
  assert.ok(removed >= 1);
  assert.equal(items.get(0).markdown, null);
  assert.equal(items.get(0).text, 'short');
  assert.equal(items.get(1).text, 'other output');
  assert.equal(streams.characters, 'shortother output'.length);
  streams.receive(notice('snapshot', ''));
  assert.equal(items.get(0).text, '');
  assert.equal(streams.characters, 'other output'.length);
  streams.receive(notice('stream_cancel'));
  streams.receive(notice('snapshot', 'late'));
  assert.equal(streams.sessions.size, 0);
  assert.equal(streams.characters, 0);
});
