import { publishBytes } from './file-io.mjs';
import { saveBoardAttachment, readBoardAttachment } from './board-files.mjs';
import { boundary } from './public/model-boundary.mjs';

export async function writeAtomic(filename, value) {
  await publishBytes(filename, JSON.stringify(value, null, 2) + '\n');
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
