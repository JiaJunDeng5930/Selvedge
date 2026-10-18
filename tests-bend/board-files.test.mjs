import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { chmod, symlink, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';
import { saveBoardAttachment, readBoardAttachment } from '../host/board-files.mjs';
import { home } from './support.mjs';

test('attachment bytes retain their hash and reads reject tampering and symlinks', async t => {
  const directory = await home(t);
  const bytes = Buffer.concat([Buffer.from([0, 255, 13, 10]), Buffer.from('原始附件 🙂')]);
  const attachment = await saveBoardAttachment(directory, 'evidence.bin',
    Readable.from([bytes.subarray(0, 7), bytes.subarray(7)]));
  assert.equal(attachment.id, createHash('sha256').update(bytes).digest('hex'));
  assert.deepEqual((await readBoardAttachment(directory, attachment.id)).data, bytes);

  await chmod(attachment.path, 0o600);
  await writeFile(attachment.path, 'tampered');
  await assert.rejects(readBoardAttachment(directory, attachment.id), /integrity/);

  // Matching bytes would pass integrity checks if the reader followed the link.
  const external = path.join(directory, 'external-content');
  await writeFile(external, bytes);
  await unlink(attachment.path);
  await symlink(external, attachment.path);
  await assert.rejects(readBoardAttachment(directory, attachment.id),
    error => ['ELOOP', 'EMLINK'].includes(error.code));
});
