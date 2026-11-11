import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';

async function eventually(read, accepted, reason) {
  const deadline = Date.now() + 10000;
  do {
    const value = await read();
    if (accepted(value)) return value;
    await delay(20);
  } while (Date.now() < deadline);
  assert.fail(reason);
}

test('the delivery picker describes queueing and steering through a real streamed response', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile } = fixture;
  const { task_id } = await command({ op: 'create_idle', profile });
  const readTask = async () => (await command({ op: 'read', task_id })).task;
  const { title } = await readTask();
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: title, exact: true }).click();
  const message = page.getByRole('combobox', { name: 'Message', exact: true });
  const send = page.getByRole('button', { name: 'Send', exact: true });
  const steer = page.getByRole('button', { name: 'Steer', exact: true });
  const delivery = page.getByRole('button', { name: /^Delivery:/ });
  const picker = page.getByRole('dialog', { name: 'Delivery', exact: true });
  const choice = title => picker.getByRole('menuitemradio', { name: title, exact: true });
  const normal = choice('Send normally');
  const redirect = choice('Steer response');
  const userInput = request => request.input.input.filter(item => item.role === 'user')
    .map(item => JSON.stringify(item.content)).join('\n');
  const requestFor = (prompt, minimumIndex = 0) => eventually(
    () => fixture.requests.find(request => request.index >= minimumIndex && userInput(request).includes(prompt)),
    Boolean, `The model did not receive ${prompt}`);

  async function assertChoice(row, title, description, checked) {
    await row.getByText(description, { exact: true }).waitFor();
    assert.equal(await row.getAttribute('aria-checked'), String(checked));
    assert.equal(await row.getByText(title, { exact: true }).count(), 1);
    const ids = (await row.getAttribute('aria-describedby')).split(/\s+/);
    assert.equal(ids.length, 1, 'Each choice explains its effect once');
  }

  await page.setViewportSize({ width: 390, height: 500 });
  await delivery.click();
  await assertChoice(normal, 'Send normally', 'Starts a new response.', true);
  await assertChoice(redirect, 'Steer response', 'Starts a new response when idle, or interrupts a response in progress.', false);
  assert.equal(await picker.getByRole('menuitemradio').count(), 2);
  await page.keyboard.press('Escape');
  await picker.waitFor({ state: 'hidden' });

  const initial = 'Start a streamed reply';
  await message.fill(initial);
  await send.click();
  const original = await requestFor(initial);
  fixture.emit(original.index, 'Streaming the original response');
  await delivery.click();
  await assertChoice(normal, 'Send normally', 'Queues behind the current response if it is still running.', true);
  await assertChoice(redirect, 'Steer response', 'Starts a new response, interrupting the current one if it is still running.', false);
  await page.keyboard.press('Escape');
  await picker.waitFor({ state: 'hidden' });

  const queued = 'Follow this response later';
  await message.fill(queued);
  await send.click();
  await eventually(readTask, task => task.queued === 1, 'The normal message never queued');
  assert.equal(fixture.requests.length, original.index + 1);
  assert.equal(original.closed, false, 'Normal delivery does not interrupt the live response');
  fixture.finish(original.index, { text: 'Original response completed' });
  const queuedReply = await requestFor(queued, original.index + 1);
  fixture.emit(queuedReply.index, 'Streaming the response to the queued message');

  const immediate = 'Change the response direction now';
  await message.fill(immediate);
  await delivery.click();
  await redirect.click();
  await picker.waitFor({ state: 'hidden' });
  assert.equal(await message.inputValue(), immediate);
  await steer.click();
  const replacement = await requestFor(immediate, queuedReply.index + 1);
  await eventually(() => queuedReply.closed, Boolean, 'Steering did not close the live provider stream');
  await eventually(() => message.inputValue(), value => value === '', 'The steering draft did not clear after submission');

  // A selected intent belongs to the unsent draft even if the active reply finishes first.
  await delivery.click();
  await redirect.click();
  await picker.waitFor({ state: 'hidden' });
  const idle = 'Start a response using the retained steering choice';
  await message.fill(idle);
  fixture.finish(replacement.index, { text: 'Redirected response' });
  await page.getByText('Redirected response', { exact: true }).waitFor();
  await delivery.click();
  await assertChoice(redirect, 'Steer response', 'Starts a new response when idle, or interrupts a response in progress.', true);
  await page.keyboard.press('Escape');
  await picker.waitFor({ state: 'hidden' });
  assert.equal(await message.inputValue(), idle);
  await steer.click();
  const final = await requestFor(idle, replacement.index + 1);
  fixture.finish(final.index, { text: 'Response from the ready conversation' });
  await page.getByText('Response from the ready conversation', { exact: true }).waitFor();
  assert.deepEqual(fixture.failures, []);
});
