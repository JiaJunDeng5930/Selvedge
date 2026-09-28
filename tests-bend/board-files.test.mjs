import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { chmod, mkdir, readFile, symlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';
import { BOARD_FILE_LIMIT, saveBoardAttachment, readBoardAttachment, observeBoardCommand } from '../host/board-files.mjs';
import { home } from './support.mjs';

test('attachment storage hashes actual bytes, retains immutable identity and distinguishes trusted preview types', async t => {
  const directory = await home(t);
  const png = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2]);
  const attachment = await saveBoardAttachment(directory, '截图.png', Readable.from([png.subarray(0, 4), png.subarray(4)]));
  assert.equal(attachment.id, createHash('sha256').update(png).digest('hex'));
  assert.equal(attachment.mime, 'image/png');
  assert.equal(attachment.bytes, String(png.length));
  assert.deepEqual((await readBoardAttachment(directory, attachment.id)).data, png);
  assert.deepEqual(await saveBoardAttachment(directory, 'another-name.png', Readable.from([png])), attachment);
  const active = Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"></svg>');
  const unsafe = await saveBoardAttachment(directory, 'looks-like-image.png', Readable.from([active]));
  assert.equal(unsafe.mime, 'application/octet-stream');
  assert.deepEqual(await readFile(unsafe.path), active);
});

test('attachment references are observed afresh; caller paths, MIME and sizes never become authority', async t => {
  const directory = await home(t);
  const attachment = await saveBoardAttachment(directory, 'notes.txt', Readable.from(['requirements']));
  const input = { op: 'create_card', title: 'Review', observed_at: '0', attachments: [{ id: attachment.id }] };
  const observed = await observeBoardCommand(input, directory);
  assert.deepEqual(observed.attachments, [attachment]);
  assert.notEqual(observed.observed_at, '0');
  assert.deepEqual(input.attachments, [{ id: attachment.id }]);
  for (const change of [{ path: '/etc/passwd' }, { mime: 'image/svg+xml' }, { bytes: '0' }, { name: '../notes.txt' }]) {
    await assert.rejects(observeBoardCommand({ ...input, attachments: [{ id: attachment.id, ...change }] }, directory), /does not match/);
  }
  await assert.rejects(observeBoardCommand({ ...input, attachments: [attachment, attachment] }, directory), /distinct/);
  await assert.rejects(observeBoardCommand({ ...input, attachments: Array(5).fill(attachment) }, directory), /four/);
  assert.deepEqual(await observeBoardCommand({ op: 'read', task_id: 0 }, directory), { op: 'read', task_id: 0 });
});

test('attachment storage rejects traversal, control characters and oversized byte streams', async t => {
  const directory = await home(t);
  for (const name of ['../outside', '/absolute', 'a\\b', '.', '..', 'line\nbreak', 'nul\0byte', 'x'.repeat(257)]) {
    await assert.rejects(saveBoardAttachment(directory, name, Readable.from(['data'])), /filename/);
  }
  for (const id of ['../outside', 'a'.repeat(63), 'A'.repeat(64), 'a'.repeat(64) + '/content']) {
    await assert.rejects(readBoardAttachment(directory, id), /identifier/);
  }
  await assert.rejects(saveBoardAttachment(directory, 'large.bin', Readable.from([Buffer.alloc(BOARD_FILE_LIMIT), Buffer.from([1])])), /10 MiB/);
});

test('attachment reads reject content tampering and symbolic-link vaults', async t => {
  const directory = await home(t);
  const attachment = await saveBoardAttachment(directory, 'notes.txt', Readable.from(['original']));
  await chmod(attachment.path, 0o600);
  await writeFile(attachment.path, 'tampered');
  await assert.rejects(readBoardAttachment(directory, attachment.id), /integrity/);
  const linked = await home(t);
  const target = path.join(linked, 'target');
  await mkdir(target);
  await symlink(target, path.join(linked, 'board-attachments'));
  await assert.rejects(saveBoardAttachment(linked, 'notes.txt', Readable.from(['safe'])), /real directory/);
});
