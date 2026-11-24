import assert from 'node:assert/strict';
import { launchChromium } from './chromium.mjs';
import { interactiveMarkdownFixture } from './interactive-markdown.mjs';
import { imagesFixture } from './images.mjs';

export const creationEnvironmentTrigger = page => page.getByRole('button', { name: '配置工作环境', exact: true });

export async function openCreationEnvironment(page) {
  const menu = page.getByRole('dialog', { name: '工作环境', exact: true });
  if (!await menu.isVisible()) await creationEnvironmentTrigger(page).click();
  await menu.waitFor();
  return menu;
}

export async function enableCreationWorktree(page) {
  const menu = await openCreationEnvironment(page);
  const toggle = menu.getByRole('menuitemcheckbox', { name: '新建工作树', exact: true });
  if (await toggle.getAttribute('aria-checked') === 'false') await toggle.click();
  await menu.getByRole('menuitemcheckbox', { name: '新建工作树', exact: true, checked: true }).waitFor();
  return menu;
}

/** Only the loopback model is controlled; pages use the complete authenticated server. */
export async function browserFixture(t, { images = false, taskTitle, cloud = false } = {}) {
  const browser = await launchChromium();
  t.after(() => browser.close());
  const fixture = images ? await imagesFixture(t) : await interactiveMarkdownFixture({ taskTitle, cloud });
  if (!images) t.after(() => fixture.close());
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
