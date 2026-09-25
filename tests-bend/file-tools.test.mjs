import test from 'node:test';
import assert from 'node:assert/strict';
import { chmod, link, readFile, readdir, stat, symlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { runFileTool } from '../host/file-tools.mjs';
import { home } from './support.mjs';

const limits = { file_bytes: 4096, file_page_bytes: 64, file_default_page_bytes: 32 };

async function tools(t) {
  const cwd = await home(t);
  const call = (name, args, options = {}) => runFileTool(name, args, limits, { cwd, ...options });
  const create = async (content, filename = 'a.txt') => {
    const result = await call('write_file', { path: filename, content, expected_revision: 'absent' });
    assert.equal(result.error, false, JSON.stringify(result));
    return result.value;
  };
  return { cwd, call, create };
}

test('UTF-8 byte pages reconstruct the original file without splitting characters or dropping its BOM', async t => {
  const { call, create } = await tools(t);
  const content = '\ufeff中文😀\r\nsecond line\n';
  const file = await create(content);
  let offset = 0;
  let reconstructed = '';
  for (;;) {
    const result = await call('read_file', { path: 'a.txt', offset, limit: 4, expected_revision: file.revision });
    assert.equal(result.error, false, JSON.stringify(result));
    reconstructed += result.value.content;
    assert.ok(Buffer.byteLength(result.value.content) <= 4);
    if (result.value.next_offset === null) break;
    assert.ok(result.value.next_offset > offset);
    offset = result.value.next_offset;
  }
  assert.equal(reconstructed, content);
  assert.equal((await call('read_file', { path: 'a.txt', offset: 1 })).value.error.code, 'invalid_offset');
  assert.equal((await call('read_file', { path: 'a.txt', offset: 999 })).value.error.code, 'invalid_offset');
  const empty = await create('', 'empty');
  const page = await call('read_file', { path: 'empty', expected_revision: empty.revision });
  assert.equal(page.value.content, '');
  assert.equal(page.value.next_offset, null);
});

test('edits require a unique literal match and a current revision, preserving newlines, BOM, and executable mode', async t => {
  const { cwd, call, create } = await tools(t);
  const file = await create('\ufefffirst\r\nhello 世界\r\n');
  await chmod(path.join(cwd, 'a.txt'), 0o751);
  const edit = await call('edit_file', { path: 'a.txt', old_text: 'hello 世界', new_text: 'goodbye 😀', expected_revision: file.revision });
  assert.equal(edit.error, false, JSON.stringify(edit));
  assert.equal(edit.value.first_changed_line, 2);
  assert.equal(await readFile(path.join(cwd, 'a.txt'), 'utf8'), '\ufefffirst\r\ngoodbye 😀\r\n');
  assert.equal((await stat(path.join(cwd, 'a.txt'))).mode & 0o777, 0o751);
  const stale = await call('write_file', { path: 'a.txt', content: 'stale', expected_revision: file.revision });
  assert.equal(stale.value.error.code, 'revision_conflict');
  const stalePage = await call('read_file', { path: 'a.txt', expected_revision: file.revision });
  assert.equal(stalePage.value.error.code, 'revision_conflict');
  const unchanged = await call('edit_file', { path: 'a.txt', old_text: 'goodbye', new_text: 'goodbye', expected_revision: edit.value.revision });
  assert.equal(unchanged.value.changed, false);
  assert.deepEqual((await readdir(cwd)).filter(name => name.startsWith('.selvedge-')), []);
});

test('ambiguous, overlapping, missing, empty, and binary replacements leave the file untouched', async t => {
  const { cwd, call, create } = await tools(t);
  const file = await create('aaaa');
  for (const [old_text, new_text, code] of [
    ['aa', 'b', 'ambiguous_edit'], ['missing', '', 'text_not_found'],
    ['', 'x', 'invalid_arguments'], ['aaaa', '\0', 'binary_file'],
  ]) {
    const result = await call('edit_file', { path: 'a.txt', old_text, new_text, expected_revision: file.revision });
    assert.equal(result.value.error.code, code);
    assert.equal(await readFile(path.join(cwd, 'a.txt'), 'utf8'), 'aaaa');
  }
});

test('concurrent writers and symlink aliases serialize against one file revision', async t => {
  const { cwd, call, create } = await tools(t);
  const file = await create('start');
  await symlink('a.txt', path.join(cwd, 'alias'));
  const results = await Promise.all(['a.txt', 'alias'].map((filename, i) => call('write_file', {
    path: filename, content: `writer ${i}`, expected_revision: file.revision,
  })));
  assert.equal(results.filter(result => !result.error).length, 1);
  assert.equal(results.find(result => result.error).value.error.code, 'revision_conflict');
  assert.equal(await readFile(path.join(cwd, 'alias'), 'utf8'), await readFile(path.join(cwd, 'a.txt'), 'utf8'));
  const creations = await Promise.all(['one', 'two'].map(content => call('write_file', { path: 'nested/new', content, expected_revision: 'absent' })));
  assert.equal(creations.filter(result => !result.error).length, 1);
  assert.equal(creations.find(result => result.error).value.error.code, 'revision_conflict');
});

test('file effects reject unsupported files and respect cancellation and byte bounds', async t => {
  const { cwd, call, create } = await tools(t);
  await writeFile(path.join(cwd, 'binary'), Buffer.from([0xff, 0xfe]));
  assert.equal((await call('read_file', { path: 'binary' })).value.error.code, 'invalid_utf8');
  await writeFile(path.join(cwd, 'nul'), Buffer.from([65, 0, 66]));
  assert.equal((await call('read_file', { path: 'nul' })).value.error.code, 'binary_file');
  await writeFile(path.join(cwd, 'large'), 'x'.repeat(limits.file_bytes + 1));
  assert.equal((await call('read_file', { path: 'large' })).value.error.code, 'file_too_large');
  assert.equal((await call('read_file', { path: '.' })).value.error.code, 'not_a_file');
  const file = await create('linked');
  await link(path.join(cwd, 'a.txt'), path.join(cwd, 'hardlink'));
  assert.equal((await call('write_file', { path: 'a.txt', content: 'new', expected_revision: file.revision })).value.error.code, 'hard_link');
  const cancelled = await call('write_file', { path: 'cancelled/child', content: 'no', expected_revision: 'absent' }, { signal: AbortSignal.abort() });
  assert.equal(cancelled.value.error.code, 'cancelled');
  const invalid = await call('write_file', { path: 'invalid/child', content: 'no', expected_revision: 'bad' });
  assert.equal(invalid.value.error.code, 'invalid_revision');
  assert.equal((await readdir(cwd)).includes('cancelled'), false);
  assert.equal((await readdir(cwd)).includes('invalid'), false);
});
