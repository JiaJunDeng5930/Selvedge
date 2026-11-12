import test from 'node:test';
import assert from 'node:assert/strict';
import { rm } from 'node:fs/promises';
import path from 'node:path';
import { browserFixture } from './fixtures/browser.mjs';

test('Settings and composer offer device-code and browser sign-in through the public audio login route', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t, { images: true });
  const { page, upstream } = fixture;
  // The image fixture supplies the real configured ChatGPT connection; remove its synthetic grant
  // so the rendered Settings and composer expose the unauthenticated sign-in flow.
  await rm(path.join(upstream.directory, upstream.profile.auth_file), { force: true });
  await fixture.restart();
  await page.goto(fixture.running.url);

  let releaseSuccess = false;
  let statusPolls = 0;
  const loginRequests = [];
  await page.route('**/api/audio/login', async route => {
    const body = route.request().postDataJSON();
    loginRequests.push(body);
    if (body.method === 'device_code') {
      return route.fulfill({ json: { attempt_id: '00000000-0000-4000-8000-000000000001',
        verification_url: 'https://auth.openai.com/codex/device', user_code: 'ABCD-EFGH',
        expires_at: new Date(Date.now() + 15 * 60_000).toISOString() } });
    }
    if (body.action === 'status') {
      statusPolls += 1;
      return route.fulfill({ json: { status: releaseSuccess ? 'signed_in' : 'pending' } });
    }
    if (body.action === 'cancel') return route.fulfill({ json: { status: 'cancelled' } });
    if (Object.keys(body).length === 0) {
      return route.fulfill({ json: { url: 'https://auth.openai.com/oauth/authorize?client_id=browser-fixture' } });
    }
    return route.fulfill({ status: 400, json: { error: 'Unexpected login request' } });
  });
  await page.context().route('https://auth.openai.com/**', route => route.fulfill({
    status: 200, contentType: 'text/html', body: '<!doctype html><title>Fixture authorization page</title>',
  }));

  const navigation = page.getByRole('navigation', { name: 'Global navigation', exact: true });
  await navigation.getByRole('button', { name: '设置', exact: true }).click();
  const settings = page.getByRole('dialog', { name: '设置', exact: true });
  await settings.getByRole('radio', { name: '模型', exact: true }).click();
  await settings.getByRole('button', { name: '使用 ChatGPT 登录', exact: true }).click();

  const chooser = page.getByRole('dialog', { name: 'Sign in with ChatGPT', exact: true });
  const firstStatusPoll = page.waitForResponse(response => response.url().includes('/api/audio/login')
    && response.request().method() === 'POST'
    && response.request().postDataJSON()?.action === 'status');
  await chooser.getByRole('button', { name: 'Use a device code', exact: true }).click();
  await chooser.getByText('ABCD-EFGH', { exact: true }).waitFor();
  const verification = chooser.getByRole('link', { name: 'Open ChatGPT verification', exact: true });
  assert.equal(await verification.getAttribute('href'), 'https://auth.openai.com/codex/device');
  await chooser.getByText('Waiting for authorization…', { exact: true }).waitFor();
  assert.equal(loginRequests[0].method, 'device_code');
  const firstPoll = await firstStatusPoll;
  assert.deepEqual(await firstPoll.json(), { status: 'pending' });
  assert.equal(statusPolls, 1, 'the device-code panel must poll its public attempt status');

  releaseSuccess = true;
  await chooser.getByText('Signed in to ChatGPT.', { exact: true }).waitFor();
  await chooser.getByRole('button', { name: 'Done', exact: true }).click();
  await settings.getByRole('button', { name: '关闭设置', exact: true }).click();

  const taskTree = page.getByRole('navigation', { name: 'Task tree', exact: true });
  await taskTree.getByRole('button', { name: '新建对话', exact: true }).click();
  const speech = page.locator('[data-voice-controls]');
  await speech.locator('summary').click();
  await speech.getByRole('button', { name: 'Sign in with ChatGPT', exact: true }).click();
  const composerChooser = page.getByRole('dialog', { name: 'Sign in with ChatGPT', exact: true });
  await composerChooser.getByRole('button', { name: 'Continue in a browser tab', exact: true }).waitFor();
  const popupPromise = page.waitForEvent('popup');
  await composerChooser.getByRole('button', { name: 'Continue in a browser tab', exact: true }).click();
  const popup = await popupPromise;
  await popup.waitForURL('https://auth.openai.com/oauth/authorize?client_id=browser-fixture');
  await popup.waitForLoadState('domcontentloaded');
  assert.deepEqual(loginRequests.at(-1), {});
});
