import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

test('conversation checklists use one marker and align wrapped text with ordinary list items', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  const { task_id } = await command({ op: 'create', profile, message: 'Show a release checklist.' });
  const checked = 'Verify the deployment checklist against all of the requirements before publishing the release.';
  const unchecked = 'Confirm the release notes.';
  const ordinary = 'The next release is on Monday.';
  const deadline = Date.now() + 10_000;
  while (!fixture.requests[0] && Date.now() < deadline) await delay(10);
  assert.ok(fixture.requests[0], 'The conversation started its model request');
  fixture.finish(0, { text: [`- [x] ${checked}`, `- [ ] ${unchecked}`, `- ${ordinary}`].join('\n') });
  const { task } = await taskIdle(running.service, task_id);
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  await page.setViewportSize({ width: 390, height: 700 });
  await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
  const timeline = page.getByRole('main').getByRole('region', { name: 'Conversation', exact: true });
  await timeline.getByText(ordinary, { exact: true }).waitFor();
  const items = timeline.getByRole('listitem');
  assert.equal(await items.count(), 3);
  const boxes = timeline.getByRole('checkbox');
  assert.equal(await boxes.count(), 2);
  assert.equal(await boxes.nth(0).isChecked(), true);
  assert.equal(await boxes.nth(1).isChecked(), false);
  assert.equal(await boxes.nth(0).isEnabled(), false);
  const geometry = await items.evaluateAll(elements => elements.map(item => {
    const marker = item.querySelector('input[type="checkbox"]')?.getBoundingClientRect();
    const text = [...item.childNodes].find(child => child.nodeType === Node.TEXT_NODE && child.textContent.trim());
    const range = document.createRange();
    range.selectNodeContents(text);
    const lines = Array.from(range.getClientRects()).filter(rect => rect.width > 0);
    return {
      bullet: getComputedStyle(item).listStyleType !== 'none',
      markerInGutter: marker && marker.left >= 0 && marker.right < lines[0].left,
      textStart: lines[0].left,
      wrapped: lines.length > 1,
      aligned: lines.every(line => Math.abs(line.left - lines[0].left) < 1),
    };
  }));
  assert.deepEqual(geometry.map(item => item.bullet), [false, false, true]);
  assert.ok(geometry[0].wrapped && geometry[0].aligned, 'Wrapped checklist text has one consistent inset');
  assert.ok(geometry[0].markerInGutter && geometry[1].markerInGutter, 'Checkboxes occupy the list gutter');
  assert.ok(Math.abs(geometry[0].textStart - geometry[2].textStart) < 1, 'Mixed list text has a shared start');
});
