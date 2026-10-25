import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';
import { imageBase64 } from './fixtures/images.mjs';
import { taskIdle } from './support.mjs';

function inputImages(value) {
  if (Array.isArray(value)) return value.flatMap(inputImages);
  if (value === null || typeof value !== 'object') return [];
  if (value.type === 'input_image') return [value];
  return Object.values(value).flatMap(inputImages);
}

function assertImageBytes(request, base64) {
  const images = inputImages(request.input);
  assert.equal(images.length, 1, 'The model request must contain exactly one image');
  assert.equal(images[0].image_url, `data:image/png;base64,${base64}`,
    'The model request must carry the exact PNG bytes copied into the browser clipboard');
}

test('pasted PNG is previewed, submitted alone and remains readable after service restart', async t => {
  const fixture = await browserFixture(t, { images: true });
  const { page } = fixture;
  const { task_id } = await fixture.command({ op: 'create', profile: fixture.profile,
    message: 'Prepare the image paste acceptance task.' });
  await taskIdle(fixture.running.service, task_id);
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: /^Image fixture task/ }).click();

  const composer = page.getByRole('combobox', { name: 'Message', exact: true });
  const initialImageCount = await page.locator('main img').count();
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write'], {
    origin: new URL(fixture.running.url).origin,
  });
  await page.evaluate(async base64 => {
    const bytes = Uint8Array.from(atob(base64), character => character.charCodeAt(0));
    await navigator.clipboard.write([
      new ClipboardItem({ 'image/png': new Blob([bytes], { type: 'image/png' }) }),
    ]);
  }, imageBase64);
  await page.evaluate(() => {
    window.__clipboardPaste = null;
    document.addEventListener('paste', async event => {
      const files = [...event.clipboardData.files];
      const bytes = files.length ? new Uint8Array(await files[0].arrayBuffer()) : new Uint8Array();
      window.__clipboardPaste = {
        files: files.map(file => ({ type: file.type, size: file.size })),
        base64: btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join('')),
      };
    }, { capture: true, once: true });
  });
  await composer.focus();
  const shortcut = await page.evaluate(() => /Mac/.test(navigator.platform) ? 'Meta+V' : 'Control+V');
  await page.keyboard.press(shortcut);
  await page.waitForFunction(() => window.__clipboardPaste !== null);
  const pasted = await page.evaluate(() => window.__clipboardPaste);
  assert.equal(pasted.files.length, 1, 'The clipboard must paste exactly one file');
  assert.ok(pasted.files.some(file => file.type === 'image/png' && file.size > 0),
    'The browser paste event must carry a PNG file');
  const clipboardDimensions = await page.evaluate(async base64 => {
    const bytes = Uint8Array.from(atob(base64), character => character.charCodeAt(0));
    const url = URL.createObjectURL(new Blob([bytes], { type: 'image/png' }));
    const image = new Image();
    image.src = url;
    await image.decode();
    URL.revokeObjectURL(url);
    return [image.naturalWidth, image.naturalHeight];
  }, pasted.base64);
  assert.deepEqual(clipboardDimensions, [2, 2], 'Chromium must decode the PNG file emitted by its clipboard');

  let hasPreview = false;
  const previewDeadline = Date.now() + 3000;
  const previews = page.locator('main img');
  while (!hasPreview && Date.now() < previewDeadline) {
    hasPreview = await previews.count() > initialImageCount;
    if (!hasPreview) await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.ok(hasPreview, 'Pasting a PNG must add its preview to the message composer');
  const preview = previews.last();
  await preview.evaluate(image => image.decode());
  assert.deepEqual(await preview.evaluate(image => [image.naturalWidth, image.naturalHeight]), [2, 2],
    'The browser must decode the pasted image before submission');
  assert.equal(await composer.inputValue(), '', 'The image-only submission must contain no text');

  const send = page.getByRole('button', { name: 'Send', exact: true });
  assert.equal(await send.isEnabled(), true, 'An image alone must be a sendable task input');
  const commandResponse = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().method() === 'POST');
  await send.click();
  const response = await commandResponse;
  assert.equal(response.status(), 200);
  const { reply } = await response.json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  await taskIdle(fixture.running.service, task_id);
  assert.equal(fixture.requests.length, 2);
  assertImageBytes(fixture.requests[1], pasted.base64);

  await fixture.restart();
  await page.reload();
  await page.getByRole('navigation', { name: 'Global navigation', exact: true }).waitFor();
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: /^Image fixture task/ }).click();
  await page.getByText('Image request accepted.', { exact: true }).first().waitFor();
  const restored = page.locator('main img').last();
  await restored.evaluate(image => image.decode());
  assert.deepEqual(await restored.evaluate(image => [image.naturalWidth, image.naturalHeight]), [2, 2],
    'The accepted image must still load and decode after service restart');

  await composer.fill('Read the earlier image again.');
  const resumedResponse = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().method() === 'POST');
  await send.click();
  const resumed = await resumedResponse;
  assert.equal(resumed.status(), 200);
  const resumedReply = await resumed.json();
  assert.equal(resumedReply.reply.ok, true, JSON.stringify(resumedReply.reply));
  await taskIdle(fixture.running.service, task_id);
  assert.equal(fixture.requests.length, 3);
  assertImageBytes(fixture.requests[2], pasted.base64);
  assert.deepEqual(fixture.upstream.failures, []);
});
