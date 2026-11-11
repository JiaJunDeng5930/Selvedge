import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

function insideViewport(bounds, { width, height }) {
  return bounds && bounds.width > 0 && bounds.height > 0 && bounds.x >= 0 && bounds.y >= 0
    && bounds.x + bounds.width <= width && bounds.y + bounds.height <= height;
}

test('new conversation settings expand below the composer at desktop and mobile sizes', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const viewports = [{ width: 1280, height: 900 }, { width: 390, height: 620 }, { width: 740, height: 390 }];
  const main = page.getByRole('main');
  const input = main.getByRole('combobox', { name: 'Task', exact: true });
  const start = main.getByRole('button', { name: 'Start task', exact: true, disabled: false });
  const environment = main.getByRole('combobox', { name: 'Run environment', exact: true });
  const summary = main.getByRole('group', { name: 'Project and run settings · Current directory', exact: true }).locator('summary');
  const message = 'Keep the task draft in place while I check its settings.';

  for (const viewport of viewports) {
    await page.setViewportSize(viewport);
    await page.reload();
    await input.fill(message);
    await start.waitFor();
    const closed = await input.boundingBox();
    const size = `${viewport.width}×${viewport.height}`;
    assert.ok(insideViewport(closed, viewport), `The input starts in view at ${size}`);
    assert.equal(await environment.isVisible(), false);

    await summary.press('Enter');
    await environment.waitFor();
    const opened = await input.boundingBox();
    assert.ok(opened && Math.abs(opened.y - closed.y) <= 2 && Math.abs(opened.x - closed.x) <= 2,
      `Opening settings keeps the input in place at ${size}`);
    assert.ok((await environment.boundingBox()).y >= opened.y + opened.height, `Settings open below the input at ${size}`);
    assert.ok(insideViewport(await start.boundingBox(), viewport), `Start stays in view at ${size}`);

    await summary.press('Enter');
    await environment.waitFor({ state: 'hidden' });
    const folded = await input.boundingBox();
    assert.ok(folded && Math.abs(folded.y - closed.y) <= 2 && Math.abs(folded.x - closed.x) <= 2,
      `Closing settings keeps the input in place at ${size}`);
    assert.equal(await input.inputValue(), message);
  }

  const short = viewports.at(-1);
  await summary.press('Enter');
  await environment.waitFor();
  await main.evaluate(node => { node.scrollTop = node.scrollHeight; });
  assert.ok(await main.evaluate(node => node.scrollTop > 0), 'The short page can scroll down to the run environment');
  assert.ok(insideViewport(await environment.boundingBox(), short));
  await start.scrollIntoViewIfNeeded();
  assert.ok(insideViewport(await start.boundingBox(), short), 'The submit button remains reachable');
});

test('collapsed new conversation settings identify the selected run environment', async t => {
  const { page } = await browserFixture(t, { cloud: true });
  const viewport = { width: 320, height: 620 };
  await page.setViewportSize(viewport);
  await page.reload();
  const main = page.getByRole('main');
  const group = main.getByRole('group', { name: /^Project and run settings · / });
  const summary = group.locator('summary');
  const environment = main.getByRole('combobox', { name: 'Run environment', exact: true });
  const cases = [
    ['New Git worktree on the Selvedge host', 'Host Git worktree'],
    ['Run on Tencent Cloud CVM', 'Tencent Cloud CVM'],
    ['Use working directory as is', 'Current directory'],
  ];
  assert.equal(await summary.textContent(), 'Project and run settings · Current directory');
  for (const [option, caption] of cases) {
    await summary.click();
    await environment.selectOption({ label: option });
    const labeledSummary = main.getByRole('group', { name: `Project and run settings · ${caption}`, exact: true }).locator('summary');
    await labeledSummary.click();
    await environment.waitFor({ state: 'hidden' });
    assert.equal(await labeledSummary.textContent(), `Project and run settings · ${caption}`);
    assert.ok(insideViewport(await labeledSummary.boundingBox(), viewport));
    assert.ok(await labeledSummary.evaluate(node => node.scrollWidth <= node.clientWidth && node.scrollHeight <= node.clientHeight),
      'The collapsed caption fits within its tappable summary at 320px');
    assert.ok(await main.evaluate(node => node.scrollWidth <= node.clientWidth), 'The creation page fits the narrow viewport');
  }
});
