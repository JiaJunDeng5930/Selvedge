import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

test('the Task model picker offers supported effort on desktop and portrait screens', async t => {
  const fixture = await browserFixture(t, { images: true });
  const { page, upstream } = fixture;
  const respond = upstream.options.respond;
  const models = [
    { slug: 'image-fixture', display_name: 'Image fixture', visibility: 'list',
      context_window: 128000, effective_context_window_percent: 100,
      default_reasoning_level: 'medium',
      supported_reasoning_levels: ['minimal', 'low', 'medium', 'high', 'xhigh'].map(effort => ({ effort })) },
    { slug: 'codex-auto-review', display_name: 'Codex auto review', visibility: 'list',
      context_window: 128000, effective_context_window_percent: 100,
      default_reasoning_level: 'medium', supported_reasoning_levels: [{ effort: 'medium' }] },
  ];
  upstream.options.respond = async (entry, response) => {
    if (new URL(entry.url, upstream.address).pathname === '/v1/models') {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ models }));
      return;
    }
    return respond(entry, response);
  };

  const refresh = await fetch(`${fixture.running.address}/api/accounts/refresh`, {
    method: 'POST',
    headers: { authorization: `Bearer ${fixture.running.token}`, 'content-type': 'application/json' },
    body: '{}',
  });
  assert.equal(refresh.status, 200, await refresh.clone().text());
  const catalog = await refresh.json();
  assert.equal(catalog.ok, true, JSON.stringify(catalog));
  assert.ok(catalog.result.profiles.some(profile =>
    profile.provider === 'chatgpt' && profile.name === 'codex-auto-review'),
  'The ChatGPT connection must advertise the hidden review model before checking the Task picker');

  await page.reload();
  await page.getByRole('navigation', { name: 'Global navigation', exact: true }).waitFor();
  const trigger = page.getByRole('button', { name: /^Model:/ });
  const picker = page.getByRole('dialog', { name: 'Model', exact: true });
  const draft = page.getByRole('combobox', { name: 'Task', exact: true });
  await draft.fill('Keep this draft while choosing a model.');
  await trigger.click();
  const profileNames = await picker.getByRole('menuitemradio').evaluateAll(options =>
    options.map(option => option.getAttribute('aria-label')));
  assert.ok(profileNames.includes('image-fixture'),
    'The ordinary Task picker should still offer a visible ChatGPT model');
  assert.ok(!profileNames.includes('codex-auto-review'),
    'The hidden ChatGPT auto-review model must not be offered as a Task model');

  await picker.getByRole('menuitemradio', { name: 'image-fixture', exact: true }).click();
  await picker.waitFor({ state: 'hidden' });
  await trigger.click();
  const effort = picker.getByRole('radiogroup', { name: 'Reasoning effort', exact: true });
  const selected = effort.getByRole('menuitemradio', { checked: true });
  const high = effort.getByRole('menuitemradio', { name: 'high', exact: true });
  await selected.waitFor();
  assert.equal(await effort.getByRole('menuitemradio').count(), 6);
  assert.equal(await high.getAttribute('aria-checked'), 'false');
  const desktop = await picker.boundingBox();
  assert.ok(desktop && desktop.width < 420, 'The desktop picker remains a compact menu');

  for (const width of [320, 390]) {
    await page.setViewportSize({ width, height: 760 });
    await page.waitForFunction(() => {
      const box = document.querySelector('dialog[aria-label="Model"][open]')?.getBoundingClientRect();
      return box && box.width > innerWidth - 36 && box.left >= 0 &&
        box.right <= innerWidth + 1 && innerHeight - box.bottom < 24;
    });
    const hitArea = await high.boundingBox();
    assert.ok(hitArea && hitArea.width >= 44 && hitArea.height >= 44);
  }
  const colors = await Promise.all([selected, high].map(choice =>
    choice.evaluate(node => getComputedStyle(node).backgroundColor)));
  assert.notEqual(colors[0], colors[1], 'The selected effort has a visible color cue');
  await high.click();
  await picker.waitFor({ state: 'hidden' });
  assert.equal(await draft.inputValue(), 'Keep this draft while choosing a model.');
  await trigger.click();
  await high.waitFor();
  assert.equal(await high.getAttribute('aria-checked'), 'true');
  await picker.getByRole('button', { name: 'Close model picker' }).click();
  await picker.waitFor({ state: 'hidden' });
});
