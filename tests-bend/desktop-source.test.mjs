import test from 'node:test';
import assert from 'node:assert/strict';
import { copyFile, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { checkDesktop } from '../scripts/import-desktop.mjs';

test('the shipped desktop artifacts retain their pinned source bytes', async () => {
  assert.match(await checkDesktop(), /match their source manifest/);
});

test('desktop provenance rejects changed code and unsafe output inventory', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-desktop-provenance-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const vendor = new URL('../host/public/vendor/', import.meta.url);
  const manifest = JSON.parse(await readFile(new URL('desktop-source.json', vendor), 'utf8'));
  for (const file of ['desktop-source.json', ...manifest.files.map(file => file.file)]) await copyFile(new URL(file, vendor), path.join(directory, file));
  await writeFile(path.join(directory, 'desktop-scroll.mjs'), 'export function createDesktopScroll() {}\n');
  await assert.rejects(checkDesktop(directory), /source mismatch: desktop-scroll/);
  manifest.files[0].file = '../app.mjs';
  await writeFile(path.join(directory, 'desktop-source.json'), JSON.stringify(manifest));
  await assert.rejects(checkDesktop(directory), /artifact inventory/);
});
