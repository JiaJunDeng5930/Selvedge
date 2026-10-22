import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

test('the ordinary Task model picker omits the hidden ChatGPT auto-review model', async t => {
  const fixture = await browserFixture(t, { images: true });
  const { page, upstream } = fixture;
  const respond = upstream.options.respond;
  const models = [
    { slug: 'image-fixture', display_name: 'Image fixture', visibility: 'list',
      context_window: 128000, effective_context_window_percent: 100,
      default_reasoning_level: 'medium', supported_reasoning_levels: [{ effort: 'medium' }] },
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
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  const profileNames = await page.getByRole('radio').evaluateAll(options =>
    options.map(option => option.getAttribute('aria-label')));
  assert.ok(profileNames.includes('image-fixture'),
    'The ordinary Task picker should still offer a visible ChatGPT model');
  assert.ok(!profileNames.includes('codex-auto-review'),
    'The hidden ChatGPT auto-review model must not be offered as a Task model');
});
