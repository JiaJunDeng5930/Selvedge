import test from 'node:test';
import assert from 'node:assert/strict';
import { MarkdownFenceObserver } from '../host/public/markdown-fences.mjs';

const frame = callback => setTimeout(() => callback(performance.now()), 1);
const cancel = clearTimeout;

test('the Markdown adapter preserves fence ordinals and full info across a split delimiter', async () => {
  const text = '    plain code\n\n```selvedge-ui extra words\nfirst\n```\n```selvedge-ui\nsecond\n```\n';
  const latest = new Map();
  const observer = new MarkdownFenceObserver({ frame, cancel, onFence: value => latest.set(value.ordinal, value) });
  try {
    const split = text.lastIndexOf('```selvedge-ui') + 2;
    observer.sync({ text: text.slice(0, split), epoch: 7n, revision: 0n, ending: 'open' });
    assert.equal(await observer.whenCaughtUp(split), true);
    observer.sync({ text, epoch: 7n, revision: 1n, ending: 'complete' });
    assert.equal(await observer.whenCaughtUp(text.length), true);
    const fences = [...latest.values()];
    assert.deepEqual(fences.map(value => value.ordinal), [0n, 1n, 2n]);
    assert.deepEqual(fences.map(value => value.kind), ['indented', 'fenced', 'fenced']);
    assert.deepEqual(fences.map(value => value.code), ['plain code', 'first', 'second']);
    assert.equal(fences[1].info, 'selvedge-ui extra words');
    assert.equal(fences[2].info, 'selvedge-ui');
    assert.equal(fences[2].infoComplete, true);
    assert.equal(fences[2].closed, true);
  } finally { observer.dispose(); }
});

test('an open component prefix can be observed before the outer document closes', async () => {
  const text = '```selvedge-ui\n<ui id="stream"><text id="ready" label="ready" />\n';
  const observations = [];
  const observer = new MarkdownFenceObserver({ frame, cancel, onFence: value => observations.push(value) });
  try {
    observer.sync({ text, epoch: 1n, revision: 3n, ending: 'open' });
    assert.equal(await observer.whenCaughtUp(text.length), true);
    assert.ok(observations.some(value => value.infoComplete && value.code.includes('label="ready"')));
    assert.equal(observations.at(-1).closed, false);
    assert.equal(observations.at(-1).inputRevision, 3n);
    const count = observations.length;
    observer.sync({ text, epoch: 1n, revision: 3n, ending: 'open' });
    await observer.whenCaughtUp(text.length);
    assert.equal(observations.length, count, 'unchanged input must not generate another semantic observation');
  } finally { observer.dispose(); }
});

test('a closed fence receives completion after ordinary Markdown continues beyond it', async () => {
  const code = '```selvedge-ui\n<ui id="tail"><button id="send" label="Send" action="submit" message="Continue" /></ui>\n```\n\n';
  const text = code + 'Ordinary Markdown after the closed interface. '.repeat(100);
  const events = [];
  const observer = new MarkdownFenceObserver({ frame, cancel, onFence: value => events.push(value) });
  try {
    observer.sync({ text: code, epoch: 9n, revision: 0n, ending: 'open' });
    assert.equal(await observer.whenCaughtUp(code.length), true);
    assert.equal(events.at(-1).closed, true);
    assert.equal(events.at(-1).ending, 'open');
    observer.sync({ text, epoch: 9n, revision: 1n, ending: 'complete' });
    assert.equal(await observer.whenCaughtUp(text.length), true);
    const terminal = events.at(-1);
    assert.equal(terminal.ordinal, 0n);
    assert.equal(terminal.closed, true);
    assert.equal(terminal.ending, 'complete');
    assert.equal(terminal.inputPrefix, text,
      'the language consumer must receive completion at the full prefix even when the fence code stopped changing earlier');
    assert.equal(terminal.inputRevision, 1n);
    assert.ok(terminal.code.includes('action="submit"'));
    assert.ok(!terminal.code.includes('Ordinary Markdown'));
  } finally { observer.dispose(); }
});
