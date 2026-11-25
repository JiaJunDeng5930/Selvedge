import { interactiveMarkdownFixture } from '../../tests/fixtures/interactive-markdown.mjs';
import { capture, launchBrowser, setViewport, viewports } from './capture.mjs';

const menus = {
  permissions: [['Custom permissions…', 'permissions-custom', [
    ['Execution policy', 'permissions-policy'],
    ['Filesystem access', 'permissions-filesystem'],
    ['Network access', 'permissions-network'],
    ['Configuration source…', 'permissions-source'],
  ]]],
  model: [
    ['Reasoning effort', 'model-effort'],
    ['Model settings…', 'model-settings', [['Configuration source…', 'model-source']]],
  ],
  workspace: [['浏览…', 'directory']],
  project: [['新建项目', 'project-editor']],
};

const key = name => `[data-semantic-key="${name}"]`;

async function captureViewport(browser, url, viewport) {
  const page = await browser.newPage({ viewport: { width: viewport.width, height: viewport.height } });
  const errors = [];
  page.on('pageerror', error => errors.push(error));
  page.setDefaultTimeout(10000);
  try {
    await page.goto(url);
    const main = page.getByRole('main');
    await main.waitFor();
    await setViewport(page, viewport);
    const modal = page.locator('dialog:modal').last();
    const button = name => modal.getByRole('button', { name, exact: true });

    async function snap(state, region = modal) {
      await region.waitFor();
      await page.mouse.move(1, 1);
      await capture(page, state, viewport);
      if (region === main && state !== 'creation') return;
      const scroll = await region.evaluateHandle(root =>
        [root, ...root.querySelectorAll('[data-surface-role="dialog-body"]')].find(box =>
          box.scrollHeight > box.clientHeight + 8 && /^(auto|scroll)$/.test(getComputedStyle(box).overflowY),
        ) ?? null);
      try {
        const original = await scroll.evaluate(box => {
          if (!box) return null;
          const top = box.scrollTop;
          box.scrollTop = box.scrollHeight;
          return box.scrollTop === top ? null : top;
        });
        if (original !== null) {
          await capture(page, state, viewport, 'bottom');
          await scroll.evaluate((box, top) => { box.scrollTop = top; }, original);
        }
      } finally {
        await scroll.dispose();
      }
    }

    await snap('creation', main);
    const workspaceTrigger = main.locator(key('composer/context')).locator(key('composer/workspace'));
    await workspaceTrigger.click();
    await snap('task-environment-options');
    await page.keyboard.press('Escape');

    for (const [kind, destinations] of Object.entries(menus)) {
      const trigger = main.locator(key(`composer/${kind}`));
      await trigger.click();
      if (kind === 'workspace') await modal.locator('button[data-logical-key="composer/workspace"]').click();
      await snap(kind);
      if (kind === 'project') {
        const search = modal.getByRole('searchbox');
        await search.fill('Documentation');
        await snap('project-search');
        await search.fill('');
      }
      for (const [label, state, subsections = []] of destinations) {
        if (!await modal.isVisible()) await trigger.click();
        await button(label).click();
        if (state === 'directory') await modal.locator('input').waitFor();
        await snap(state);
        for (const [sectionLabel, sectionState] of subsections) {
          await button(sectionLabel).click();
          await snap(sectionState);
          await button('Back').click();
        }
        if (state.startsWith('model-') || state === 'permissions-custom') {
          await button('Back').click();
        } else {
          await page.keyboard.press('Escape');
        }
      }
      for (let depth = 0; depth < 5 && await modal.isVisible(); depth++) await page.keyboard.press('Escape');
      if (await modal.isVisible()) throw new Error(`${kind} did not close`);
    }
    if (errors.length) throw new AggregateError(errors, `Page errors at ${viewport.id}`);
  } finally {
    await page.close();
  }
}

const fixture = await interactiveMarkdownFixture();
try {
  const { reply } = await fixture.command({
    op: 'create_project', name: 'Documentation and onboarding',
    workspace: { roots: [fixture.root], primary_root: fixture.root },
  });
  if (!reply.ok) throw new Error(`Could not seed the project chooser: ${JSON.stringify(reply)}`);
  const browser = await launchBrowser();
  try {
    const failures = [];
    for (const viewport of viewports) {
      try {
        await captureViewport(browser, fixture.running.url, viewport);
      } catch (error) {
        // DEFENSE: A changed browser control can stop one viewport's flow.
        // Keep that failure visible and continue the independent viewports.
        console.error(`${viewport.id}:`, error);
        failures.push(error);
      }
    }
    if (failures.length) throw new AggregateError(failures, 'Property screenshots incomplete');
  } finally {
    await browser.close();
  }
} finally {
  await fixture.close();
}
