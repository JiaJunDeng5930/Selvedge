import { setTimeout as delay } from 'node:timers/promises';
import { interactiveMarkdownFixture } from '../../tests/fixtures/interactive-markdown.mjs';
import { capture, launchBrowser, setViewport, viewports } from './capture.mjs';
import { viewports as catalogViewports } from './catalog.mjs';

const desktop = catalogViewports.find(({ id }) => id === 'desktop');
const narrow = catalogViewports.find(({ id }) => id === 'narrow');
const profile = 'interactive';
const approvalSettings = { approval: { mode: 'ask-for-approval' } };
const key = name => `[data-semantic-key="${name}"]`;
const button = (scope, name) => scope.getByRole('button', { name, exact: true });
const expandedActivity = '[data-surface-role="activity"][data-expanded="true"]';

const sourceReply = [
  'Check how the conversation displays prose and source code at each window size.',
  '',
  '```shell',
  'printf "%s\\n" "A very long command belongs to a dedicated horizontal scroll region and must never widen the assistant message, sidebar, or composer."',
  '```',
  '',
  'The result contains one unbroken token: ' + 'UnbrokenToken'.repeat(15) + '.',
  '',
  '- First reading check',
  '- Second reading check',
].join('\n');

async function requestFor(fixture, prompt) {
  const deadline = Date.now() + 10_000;
  do {
    const request = fixture.requests.find(entry => !entry.closed && entry.input.input.some(item =>
      item.role === 'user' && JSON.stringify(item.content).includes(prompt)));
    if (request) return request.index;
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error(`The fixture did not receive the model request: ${prompt}`);
}

function scrollTo(locator, block) {
  return locator.evaluate((node, position) => node.scrollIntoView({ block: position, inline: 'nearest' }), block);
}

function scrollToEnd(locator) {
  return locator.evaluate(node => { node.scrollTop = node.scrollHeight; });
}

async function showRetainedNotice(page, notice) {
  // Wheel input detaches the reading view from its automatic following of the reply.
  for (let attempt = 0; attempt < 3; attempt++) {
    const target = await notice.evaluate(node => {
      const timeline = node.closest('[data-reading-root]').getBoundingClientRect();
      const notice = node.getBoundingClientRect();
      if (notice.top >= timeline.top && notice.bottom <= timeline.bottom) return null;
      return { x: timeline.left + 10, y: timeline.top + timeline.height / 2, delta: notice.top - timeline.top - 8 };
    });
    if (!target || Math.abs(target.delta) < 2) return;
    await page.mouse.move(target.x, target.y);
    await page.mouse.wheel(0, target.delta);
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  }
}

async function captureConversation(page, fixture) {
  page.setDefaultTimeout(10_000);
  await page.goto(fixture.running.url);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true }).waitFor();
  await setViewport(page, desktop);

  const main = page.getByRole('main');
  const composer = main.locator('[data-composer-dock]');
  const conversation = main.locator('[data-view]');
  const side = page.locator(key('side-conversation'));
  const details = page.locator(key('task-details'));
  const actions = main.locator(key('task-actions'));
  const menu = page.locator(`dialog${key('object-actions')}`);
  const editor = page.locator(`dialog${key('object-editor')}`);
  const preview = page.locator(`dialog${key('file-preview')}`);

  async function atEachSize(run) {
    for (const viewport of viewports) {
      await setViewport(page, viewport);
      await page.mouse.move(1, 1);
      await run(viewport);
    }
  }

  async function command(input) {
    const { reply } = await fixture.command(input);
    if (!reply.ok) throw new Error(`Fixture command ${input.op} failed: ${JSON.stringify(reply)}`);
    return reply.result;
  }

  async function openTask(title) {
    await setViewport(page, desktop);
    await button(page, title).click();
  }

  const title = 'Read a long shell command safely';
  await command({ op: 'create', profile, message: title, settings: approvalSettings });
  fixture.finish(await requestFor(fixture, title), { text: sourceReply });
  await openTask(title);
  await main.getByText('Second reading check', { exact: true }).waitFor();

  await atEachSize(async viewport => {
    await scrollTo(main.locator('.code-block'), 'center');
    await capture(page, 'main', viewport);

    await button(main, 'Expand activity').last().click();
    await scrollTo(main.locator(expandedActivity), 'center');
    await capture(page, 'audit-expanded', viewport);
    await button(main, 'Collapse activity').last().click();

    const wrap = main.locator('.code-toolbar button[aria-pressed]');
    await wrap.click();
    await scrollTo(main.locator('.code-block'), 'center');
    await capture(page, 'code-wrap', viewport);
    await wrap.click();

    const voice = composer.locator('details[data-voice-controls]');
    await voice.locator('summary').click();
    await voice.locator('[data-voice-controls-body]').waitFor();
    await capture(page, 'voice', viewport);
    await voice.locator('summary').click();
  });

  await setViewport(page, desktop);
  const message = composer.locator('textarea');
  await message.fill('/side');
  await message.press('Enter');
  await side.waitFor();
  await atEachSize(async viewport => {
    await scrollTo(side.locator('.code-block'), 'center');
    await capture(page, 'side', viewport);
  });
  await button(side, '关闭').click();
  await side.waitFor({ state: 'hidden' });

  await atEachSize(async viewport => {
    await button(actions, 'Task details').click();
    await details.waitFor();
    const body = details.locator('[data-surface-role="dialog-body"]');
    await body.evaluate(node => { node.scrollTop = 0; });
    await capture(page, 'task-details', viewport);
    await scrollToEnd(body);
    await capture(page, 'task-details', viewport, 'bottom');
    await button(details, 'Close panel').or(button(details, 'Task details')).click();
    await details.waitFor({ state: 'hidden' });

    await button(actions, 'More actions').click();
    await menu.waitFor();
    await capture(page, 'task-actions', viewport);
    for (const name of ['Fork', 'Compact']) {
      await button(menu, name).or(menu.getByRole('menuitem', { name, exact: true })).click();
      await editor.waitFor();
      await capture(page, name.toLowerCase(), viewport);
      await page.keyboard.press('Escape');
      await editor.waitFor({ state: 'hidden' });
      if (!await menu.isVisible()) await button(actions, 'More actions').click();
      await menu.waitFor();
    }
    await page.keyboard.press('Escape');
    await menu.waitFor({ state: 'hidden' });
  });

  // Use a portrait capture of the isolated session as the PNG to preview.
  await setViewport(page, narrow);
  const attachment = await page.screenshot({ animations: 'disabled', scale: 'css' });
  const file = composer.locator('input[type=file]');
  await file.setInputFiles({
    name: 'A detailed screenshot of the conversation for the attached notes.png',
    mimeType: 'image/png',
    buffer: attachment,
  });
  await button(composer, 'Preview').waitFor();

  await atEachSize(async viewport => {
    await capture(page, 'attachment', viewport);
    await button(composer, 'Preview').click();
    const image = preview.locator(`img${key('preview-image')}`);
    await image.waitFor();
    await image.evaluate(node => node.decode());
    await capture(page, 'preview', viewport);
    await button(preview, 'Close preview').click();
    await preview.waitFor({ state: 'hidden' });
  });

  await file.setInputFiles({
    name: 'unsupported.txt',
    mimeType: 'text/plain',
    buffer: Buffer.from('unsupported'),
  });
  await composer.getByText('Upload failed', { exact: true }).waitFor();
  await atEachSize(async viewport => {
    await capture(page, 'upload-error', viewport);
    if (viewport.id === 'large') {
      await button(composer, 'Remove failed upload').scrollIntoViewIfNeeded();
      await scrollToEnd(conversation);
      await capture(page, 'upload-error', viewport, 'bottom');
    }
  });

  const approvalTitle = 'Review the pending shell command';
  await command({ op: 'create', profile, message: approvalTitle, settings: approvalSettings });
  fixture.finish(await requestFor(fixture, approvalTitle), { output: [{
    type: 'function_call',
    call_id: 'screenshot-approval',
    name: 'bash',
    arguments: JSON.stringify({
      command: 'printf "%s\\n" "This command shows how the approval panel wraps a long argument."',
      sandbox_permissions: 'require_escalated',
      justification: 'Review the requested working directory and current approval policy first.',
      timeout_ms: 5000,
    }),
  }] });
  await openTask(approvalTitle);
  await main.locator('[data-surface-role="approval"]').waitFor();
  await atEachSize(async viewport => {
    await capture(page, 'approval', viewport);
    if (viewport.id === 'large') {
      await scrollToEnd(conversation);
      await capture(page, 'approval', viewport, 'bottom');
    }
  });

  const { task_id: idleTaskId } = await command({ op: 'create_idle', profile });
  const { task: idleTask } = await command({ op: 'read', task_id: idleTaskId });
  await openTask(idleTask.title);
  await composer.locator('textarea').waitFor();
  await atEachSize(viewport => capture(page, 'blank-conversation', viewport));

  const streamingTitle = 'Read a retained partial reply';
  const { task_id: streamingTaskId } = await command({ op: 'create', profile, message: streamingTitle });
  const streamingRequest = await requestFor(fixture, streamingTitle);
  await openTask(streamingTitle);
  const opening = 'The visibly streaming answer remains present';
  fixture.emit(streamingRequest, `${opening} before it is committed. This fixture interrupts the operation before completion.`);
  // A pending Markdown paragraph can hold back its trailing punctuation.
  await main.locator(key('generated-output')).getByText(opening).waitFor();
  await atEachSize(viewport => capture(page, 'streaming', viewport));

  await command({ op: 'interrupt', task_id: streamingTaskId });
  const notice = main.locator(key('unfinished-notice'));
  await notice.waitFor();
  await atEachSize(async viewport => {
    await showRetainedNotice(page, notice);
    await capture(page, 'unfinished-reply', viewport);
  });

  const failureTitle = 'Inspect a failed tool call';
  await command({ op: 'create', profile, message: failureTitle });
  fixture.finish(await requestFor(fixture, failureTitle), { output: [{
    type: 'function_call',
    call_id: 'missing-task',
    name: 'read_task',
    arguments: JSON.stringify({ task_id: 987654321 }),
  }] });
  await openTask(failureTitle);
  await atEachSize(async viewport => {
    await scrollTo(main.locator(expandedActivity).last(), 'center');
    await capture(page, 'failed-tool', viewport);
  });
}

const fixture = await interactiveMarkdownFixture();
let browser;
try {
  browser = await launchBrowser();
  await captureConversation(await browser.newPage(), fixture);
} finally {
  try {
    await browser?.close();
  } finally {
    await fixture.close();
  }
}
