import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { browserFixture } from './fixtures/browser.mjs';

async function projectFixture(t) {
  const fixture = await browserFixture(t);
  const workspace = path.join(fixture.root, 'Disconnect admission workspace');
  await mkdir(workspace);
  await fixture.command({ op: 'create_project', name: 'Disconnect admission project',
    workspace: { roots: [workspace], primary_root: workspace } });
  const { page } = fixture;
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('region', { name: 'Disconnect admission project', exact: true }).hover();
  return fixture;
}

async function editorFixture(t) {
  const fixture = await projectFixture(t);
  const { page } = fixture;
  await page.getByRole('main').getByRole('button', { name: 'Project actions', exact: true }).click();
  await page.getByRole('button', { name: 'Project details', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: 'New task', exact: true }).click();
  return fixture;
}

async function disconnectAndAdmit(page, operation, disconnect) {
  const assessment = page.waitForResponse(response => response.url().endsWith('/api/assess')
    && response.request().method() === 'POST'
    && response.request().postDataJSON()?.command?.op === operation);
  disconnect();
  const response = await assessment;
  assert.equal(response.status(), 200, await response.text());
  const result = await response.json();
  assert.equal(result.admitted, true, 'The browser must receive a fresh, accepted assessment after disconnect');
}

test('a disconnected service keeps the editor Submit unavailable after fresh admission', { timeout: 60000 }, async t => {
  const fixture = await editorFixture(t);
  const { page, running } = fixture;
  const submit = page.getByRole('button', { name: 'Start task', exact: true });
  await submit.waitFor();
  await page.getByRole('textbox', { name: 'Task', exact: true }).fill('Keep this draft while the service is disconnected.');
  await page.getByRole('button', { name: 'Start task', exact: true, disabled: false }).waitFor();

  let commands = 0;
  page.on('request', request => {
    if (request.url().endsWith('/api/browser/command') && request.method() === 'POST') commands++;
  });
  await disconnectAndAdmit(page, 'create', () => running.disconnect());
  await page.getByRole('button', { name: 'Start task', exact: true, disabled: true }).waitFor();
  assert.equal(commands, 0, 'The disabled Submit control must not dispatch a command');
});

test('an open confirmation stays unavailable after disconnect and fresh admission', { timeout: 60000 }, async t => {
  const fixture = await projectFixture(t);
  const { page, running } = fixture;
  await page.getByRole('main').getByRole('button', { name: 'Project actions', exact: true }).click();
  await page.getByRole('button', { name: 'Delete project', exact: true }).click();
  const confirm = page.getByRole('dialog').getByRole('button', { name: 'Confirm', exact: true });
  await confirm.waitFor();
  await page.getByRole('dialog').getByRole('button', { name: 'Confirm', exact: true, disabled: false }).waitFor();

  let commands = 0;
  page.on('request', request => {
    if (request.url().endsWith('/api/browser/command') && request.method() === 'POST') commands++;
  });
  await disconnectAndAdmit(page, 'delete_project', () => running.disconnect());
  await page.getByRole('dialog').getByRole('button', { name: 'Confirm', exact: true, disabled: true }).waitFor();
  assert.equal(commands, 0, 'The disabled Confirm control must not dispatch a command');
});
