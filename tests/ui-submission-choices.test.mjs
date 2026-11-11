import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

test('the Task model picker switches between its model list and effort control at every viewport', async t => {
  const fixture = await browserFixture(t, { images: true });
  const { page, upstream } = fixture;
  const respond = upstream.options.respond;
  const models = [
    { slug: 'image-fixture', display_name: 'Image fixture', visibility: 'list',
      context_window: 128000, effective_context_window_percent: 100,
      default_reasoning_level: 'medium',
      supported_reasoning_levels: ['minimal', 'low', 'medium', 'high', 'xhigh'].map(effort => ({ effort })) },
    ...Array.from({ length: 12 }, (_, index) => ({
      slug: `model-fixture-${index + 1}`, display_name: `Model ${index + 1}`, visibility: 'list',
      context_window: 128000, effective_context_window_percent: 100,
      default_reasoning_level: 'medium',
      supported_reasoning_levels: ['minimal', 'low', 'medium', 'high', 'xhigh'].map(effort => ({ effort })),
    })),
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
  const search = picker.getByRole('searchbox', { name: 'Search models' });
  const model = name => picker.getByRole('menuitemradio', { name, exact: true });
  const catalogBox = picker.locator('[data-semantic-key="model-picker-models"]');
  const summary = picker.getByRole('button', { name: /^Choose model:/ });
  const effort = picker.getByRole('slider', { name: 'Reasoning effort' });

  await trigger.click();
  await Promise.any([summary.waitFor(), catalogBox.waitFor()]);
  if (await summary.isVisible()) await summary.click();
  await catalogBox.waitFor();
  await effort.waitFor({ state: 'hidden' });
  const profileNames = await catalogBox.getByRole('menuitemradio').evaluateAll(options =>
    options.map(option => option.getAttribute('aria-label')));
  assert.ok(profileNames.includes('image-fixture'),
    'The ordinary Task picker should still offer a visible ChatGPT model');
  assert.ok(!profileNames.includes('codex-auto-review'),
    'The hidden ChatGPT auto-review model must not be offered as a Task model');
  await model('image-fixture').click();
  await summary.waitFor();
  await effort.waitFor();
  assert.equal(await effort.getAttribute('aria-valuetext'), 'Default');
  assert.equal(await effort.getAttribute('max'), '5');

  for (const [width, height] of [[1280, 900], [760, 390], [320, 760], [390, 760]]) {
    await page.setViewportSize({ width, height });
    await summary.waitFor();
    await catalogBox.waitFor({ state: 'hidden' });
    const portrait = height > width;
    await page.waitForFunction(portrait => {
      const box = document.querySelector('dialog[aria-label="Model"][open]')?.getBoundingClientRect();
      return box && box.left >= 0 && box.right <= innerWidth + 1 && box.top >= 0 &&
        box.height < 190 && (portrait
          ? box.width > innerWidth - 36 && innerHeight - box.bottom < 24
          : box.width < 340 && box.bottom <= innerHeight);
    }, portrait);
    const track = await effort.boundingBox();
    assert.ok(track && track.width > 200 && track.height >= (portrait ? 44 : 30));
  }

  await effort.focus();
  await page.keyboard.press('End');
  await page.waitForFunction(() =>
    document.querySelector('input[data-model-effort-range]')?.getAttribute('aria-valuetext') === 'xhigh');
  assert.match(await summary.innerText(), /image-fixture\s*xhigh/i);
  const bounds = await effort.boundingBox();
  const y = bounds.y + bounds.height / 2;
  await page.mouse.move(bounds.x + bounds.width - 15, y);
  await page.mouse.down();
  await page.mouse.move(bounds.x + 15, y, { steps: 5 });
  await page.waitForFunction(() =>
    document.querySelector('input[data-model-effort-range]')?.getAttribute('aria-valuetext') === 'Default');
  await page.mouse.up();
  await summary.getByText('Default', { exact: true }).waitFor();

  await summary.click();
  await catalogBox.waitFor();
  await search.waitFor();
  await effort.waitFor({ state: 'hidden' });
  const searchBeforeScroll = await search.boundingBox();
  assert.ok((await catalogBox.getByRole('menuitemradio').count()) > 10);
  await catalogBox.evaluate(node => { node.scrollTop = node.scrollHeight; });
  assert.ok(await catalogBox.evaluate(node => node.scrollTop > 0), 'The long catalog has its own scroll area');
  assert.deepEqual(await search.boundingBox(), searchBeforeScroll, 'The search stays above the scrolling list');
  await picker.getByRole('button', { name: 'Back to reasoning effort' }).click();
  await summary.waitFor();
  assert.equal(await effort.getAttribute('aria-valuetext'), 'Default');
  await summary.click();
  await search.fill('model-fixture-12');
  await model('model-fixture-1').waitFor({ state: 'hidden' });
  assert.equal(await search.inputValue(), 'model-fixture-12');
  await model('model-fixture-12').click();
  await summary.getByText('model-fixture-12', { exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await picker.waitFor({ state: 'hidden' });
  assert.match(await trigger.getAttribute('aria-label'), /model-fixture-12/);
  assert.equal(await draft.inputValue(), 'Keep this draft while choosing a model.');
});
