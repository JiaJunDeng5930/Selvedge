import { open } from 'node:fs/promises';
import { constants } from 'node:fs';

/** Read one bounded control-file revision without following replaced links. */
export async function readControlRecord(filename, { maximumBytes, label }) {
  const file = await open(filename, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW);
  try {
    const before = await file.stat();
    // DEFENSE: A persisted control file can be replaced by a special or oversized file.
    if (!before.isFile() || before.size > maximumBytes) throw new Error(`Invalid ${label}`);
    const buffer = Buffer.alloc(before.size + 1);
    let length = 0;
    while (length < buffer.length) {
      const { bytesRead } = await file.read(buffer, length, buffer.length - length, length);
      if (!bytesRead) break;
      length += bytesRead;
    }
    const after = await file.stat();
    // DEFENSE: External edits during the read must not assemble different control-file revisions.
    if (length !== before.size || after.size !== before.size ||
        after.mtimeMs !== before.mtimeMs || after.ctimeMs !== before.ctimeMs) {
      throw new Error(`${label[0].toUpperCase()}${label.slice(1)} changed while being read`);
    }
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(buffer.subarray(0, length)));
  } finally { await file.close(); }
}
