import { mkdir, open, rename, unlink } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { saveBoardAttachment, readBoardAttachment } from './board-files.mjs';
import { boundary } from './public/model-boundary.mjs';

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
    // DEFENSE: A successful rename removes the temporary name; failed writes still need their temporary file removed.
    await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
  }
}

/** Freeze image bytes in the existing content-addressed attachment vault. */
export async function storeImageContent(home, name, bytes, detail = 'auto') {
  const attachment = await saveBoardAttachment(home, name, [bytes]);
  return boundary('backend.image_content', { attachment, detail });
}

/** Resolve only a native image slot; byte and metadata integrity belong to the vault. */
export async function imageDataURL(home, expected) {
  const { attachment, data } = await readBoardAttachment(home, expected.id);
  boundary('backend.image_materialized', { expected, attachment });
  return `data:${attachment.mime};base64,${data.toString('base64')}`;
}
