import { mkdir, open, rename, unlink } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import path from 'node:path';

export async function writeAtomic(filename, value) {
  const directory = path.dirname(filename);
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const temporary = `${filename}.${randomUUID()}.tmp`;
  try {
    const file = await open(temporary, 'wx', 0o600);
    try { await file.writeFile(JSON.stringify(value, null, 2) + '\n'); await file.sync(); }
    finally { await file.close(); }
    await rename(temporary, filename);
    const parent = await open(directory, 'r');
    try { await parent.sync(); } finally { await parent.close(); }
  } finally {
    await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
  }
}
