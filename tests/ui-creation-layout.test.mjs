import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture, creationEnvironmentTrigger, openCreationEnvironment } from './fixtures/browser.mjs';

function insideViewport(bounds, { width, height }) {
  return bounds && bounds.width > 0 && bounds.height > 0 && bounds.x >= -1 && bounds.y >= -1
    && bounds.x + bounds.width <= width + 1 && bounds.y + bounds.height <= height + 1;
}

function iconWithoutCaption(button) {
  return button.evaluate(node => [...node.childNodes].every(child => {
    if (child.nodeType === Node.TEXT_NODE) return child.textContent.trim() === '';
    return child instanceof SVGElement ||
      child instanceof HTMLElement && getComputedStyle(child).clipPath === 'inset(50%)';
  }));
}

test('the composer gear opens upward and preserves the draft at desktop and mobile sizes', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const viewports = [{ width: 1280, height: 900 }, { width: 390, height: 620 },
    { width: 740, height: 390 }, { width: 320, height: 620 }];
  const main = page.getByRole('main');
  const input = main.getByRole('combobox', { name: 'Task', exact: true });
  const start = main.getByRole('button', { name: 'Start task', exact: true, disabled: false });
  const gear = creationEnvironmentTrigger(page);
  const settings = page.getByRole('dialog', { name: '工作环境', exact: true });
  const message = 'Keep the task draft in place while I check its settings.';

  for (const viewport of viewports) {
    await page.setViewportSize(viewport);
    await page.reload();
    await input.fill(message);
    await start.waitFor();
    const closed = await input.boundingBox();
    const trigger = await gear.boundingBox();
    const size = `${viewport.width}×${viewport.height}`;
    assert.ok(insideViewport(closed, viewport) && insideViewport(trigger, viewport), size);
    assert.ok(trigger.y >= closed.y + closed.height - 2, 'The gear is in the input toolbar');
    assert.equal(await gear.locator('svg').count(), 1);
    assert.equal(await iconWithoutCaption(gear), true, 'The closed control only paints a gear');
    assert.equal(await settings.isVisible(), false);

    await gear.press('Enter');
    await settings.waitFor();
    const opened = await input.boundingBox();
    const panel = await settings.boundingBox();
    assert.ok(opened && Math.abs(opened.y - closed.y) <= 2 && Math.abs(opened.x - closed.x) <= 2,
      `Opening settings keeps the input in place at ${size}`);
    assert.ok(insideViewport(panel, viewport), `The menu fits the viewport at ${size}`);
    assert.ok(panel.y + panel.height <= trigger.y + 2, `The menu opens above its gear at ${size}`);
    assert.ok(insideViewport(await start.boundingBox(), viewport), `Start stays in view at ${size}`);

    await page.keyboard.press('Escape');
    await settings.waitFor({ state: 'hidden' });
    await page.waitForFunction(() => document.activeElement?.dataset.semanticKey === 'composer/environment');
    assert.equal(await input.inputValue(), message);
  }
});

test('project and directory choices open inside the composer menu and return to it', async t => {
  const { page } = await browserFixture(t);
  const menu = await openCreationEnvironment(page);
  await menu.locator('button[data-logical-key="composer/project"]').click();
  const project = page.getByRole('dialog', { name: 'Choose project', exact: true });
  await project.waitFor();
  assert.equal(await menu.isVisible(), false);
  await project.getByRole('button', { name: '返回工作环境', exact: true }).click();
  await menu.waitFor();
  assert.equal(await project.isVisible(), false);

  await menu.locator('button[data-logical-key="composer/workspace"]').click();
  const workspace = page.getByRole('dialog', { name: 'Workspace', exact: true });
  await workspace.waitFor();
  assert.equal(await menu.isVisible(), false);
  await page.keyboard.press('Escape');
  await menu.waitFor();
  assert.equal(await workspace.isVisible(), false);
  await page.keyboard.press('Escape');
  await menu.waitFor({ state: 'hidden' });
});

test('configured run environments show the current choice in the gear menu', async t => {
  const { page } = await browserFixture(t, { cloud: true });
  const viewport = { width: 320, height: 620 };
  await page.setViewportSize(viewport);
  await page.reload();
  const menu = await openCreationEnvironment(page);
  const choice = (name, checked) => menu.getByRole('menuitemradio', { name, exact: true, checked });
  const cases = ['New Git worktree on the Selvedge host', 'Run on Tencent Cloud CVM', 'Use working directory as is'];
  await choice(cases[2], true).waitFor();
  for (const name of cases) {
    await choice(name, false).click();
    await choice(name, true).waitFor();
    assert.ok(insideViewport(await menu.boundingBox(), viewport));
    assert.equal(await iconWithoutCaption(creationEnvironmentTrigger(page)), true);
  }
});
