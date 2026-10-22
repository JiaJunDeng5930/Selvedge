import assert from 'node:assert/strict';
import { access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { chromium } from 'playwright-core';
import { interactiveMarkdownFixture } from './interactive-markdown.mjs';
import { imagesFixture } from './images.mjs';

async function chromiumExecutable() {
  const requested = process.env.SELVEDGE_CHROMIUM_EXECUTABLE_PATH;
  if (requested) {
    await access(requested, constants.X_OK);
    return requested;
  }
  for (const filename of ['/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome']) {
    try {
      await access(filename, constants.X_OK);
      return filename;
    } catch (error) {
      // DEFENSE: Linux distributions install Chromium under different executable names.
      if (error.code !== 'ENOENT') throw error;
    }
  }
  throw new Error('Browser acceptance requires Chromium. Install it or set SELVEDGE_CHROMIUM_EXECUTABLE_PATH.');
}

/** Only the loopback model is controlled; pages use the complete authenticated server. */
export async function browserFixture(t, { images = false } = {}) {
  const fixture = images ? await imagesFixture(t) : await interactiveMarkdownFixture();
  if (!images) t.after(() => fixture.close());
  const browser = await chromium.launch({ executablePath: await chromiumExecutable(), headless: true });
  t.after(() => browser.close());
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  page.setDefaultTimeout(10000);
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  t.after(() => assert.deepEqual(errors, [], 'The browser must remain operational throughout the workflow'));
  async function command(value) {
    const response = await fetch(`${fixture.running.address}/api/commands`, {
      method: 'POST', headers: { authorization: `Bearer ${fixture.running.token}`, 'content-type': 'application/json' },
      body: JSON.stringify(value),
    });
    assert.equal(response.status, 200, await response.clone().text());
    const reply = await response.json();
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  }
  await page.goto(fixture.running.url);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true }).waitFor();
  return { ...fixture, get running() { return fixture.running; }, page, browser, command,
    profile: images ? fixture.profile : 'interactive' };
}
