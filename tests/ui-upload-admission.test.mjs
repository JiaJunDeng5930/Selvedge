import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { browserFixture } from './fixtures/browser.mjs';

test('a normal Task composer rejects a stored text file without making it a submittable attachment', async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const workspace = path.join(fixture.root, 'Upload admission workspace');
  await mkdir(workspace);
  await command({ op: 'create_project', name: 'Upload admission project',
    workspace: { roots: [workspace], primary_root: workspace } });

  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('region', { name: 'Upload admission project', exact: true }).hover();
  await page.getByRole('main').getByRole('button', { name: 'Project actions', exact: true }).click();
  await page.getByRole('button', { name: 'Project details', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: 'New task', exact: true }).click();

  const task = page.getByRole('textbox', { name: 'Task', exact: true });
  const start = page.getByRole('button', { name: 'Start task', exact: true });
  await task.waitFor();
  assert.equal(await start.isDisabled(), true, 'An empty Task starts as a passive draft');

  const filename = 'ordinary-notes.txt';
  const file = path.join(fixture.root, filename);
  const contents = 'This ordinary text file is not a supported image attachment.';
  await writeFile(file, contents);
  const uploadReceipt = page.waitForResponse(response => new URL(response.url()).pathname === '/api/board/attachments'
    && response.request().method() === 'POST');
  await page.locator('input[type="file"]').first().setInputFiles(file);
  const upload = await uploadReceipt;
  assert.equal(upload.status(), 201, 'The shared upload endpoint finishes storing the actual file');

  await page.getByText(/(?=.*PNG)(?=.*JPEG)(?=.*GIF)(?=.*WebP)(?=.*10\s*MiB)/is).waitFor();
  assert.equal(await task.inputValue(), '', 'Rejecting the upload leaves the Task message unchanged');
  assert.equal(await page.getByRole('main').getByText(filename, { exact: true }).count(), 0,
    'The rejected file is not rendered as a Task attachment');
  assert.equal(await start.isDisabled(), true, 'The rejected file cannot make an empty Task submittable');
});
