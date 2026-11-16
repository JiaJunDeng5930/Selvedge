import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { gzipSync, gunzipSync } from 'node:zlib';
import { publishBytes, readBoundedRegularSnapshot } from './file-io.mjs';

const format = 'selvedge-journal-checkpoint-2';
const macBytes = 32;
const maximumBytes = 64 * 1024 * 1024;

async function readCacheFile(filename, maximumBytes, admitMetadata) {
  try {
    return (await readBoundedRegularSnapshot(filename, { maximumBytes, admitMetadata })).bytes;
  } catch (error) {
    // DEFENSE: The optional cache can be absent, replaced during publication, or left with unusable files.
    if (['ENOENT', 'ELOOP', 'NOT_REGULAR', 'CHANGED', 'TOO_LARGE', 'CHECKPOINT_KEY_PERMISSIONS'].includes(error.code)) return;
    throw error;
  }
}

export class JournalCheckpoint {
  constructor(journalFilename, journalFormat) {
    this.filename = `${journalFilename}.checkpoint`;
    this.keyFilename = `${this.filename}.key`;
    this.journalFormat = journalFormat;
  }

  async #readKey() {
    const key = await readCacheFile(this.keyFilename, macBytes, metadata => {
      // DEFENSE: A copied service home can contain a key writable or readable outside its owner.
      if (metadata.uid !== process.getuid() || (metadata.mode & 0o077) !== 0) {
        throw Object.assign(new Error('Journal checkpoint key is not private'), { code: 'CHECKPOINT_KEY_PERMISSIONS' });
      }
    });
    return key?.length === macBytes ? key : undefined;
  }

  async read(namespace) {
    const key = await this.#readKey();
    if (!key) return;
    const bytes = await readCacheFile(this.filename, maximumBytes);
    // DEFENSE: A truncated or edited checkpoint must never reach the native decoder.
    if (!bytes || bytes.length <= macBytes) return;
    const signed = bytes.subarray(macBytes);
    const mac = createHmac('sha256', key).update(signed).digest();
    if (!timingSafeEqual(mac, bytes.subarray(0, macBytes))) return;
    const separator = signed.indexOf(10);
    const header = JSON.parse(signed.subarray(0, separator).toString('utf8'));
    if (header.format !== format || header.namespace !== namespace || header.journalFormat !== this.journalFormat) return;
    const payload = gunzipSync(signed.subarray(separator + 1), { maxOutputLength: maximumBytes });
    return { ...header, payload };
  }

  // Only the owner of the committed journal can publish an authenticated checkpoint.
  async write(namespace, sequence, prefix, { schema, data }) {
    const header = `${JSON.stringify({ format, namespace, sequence, prefix, schema, journalFormat: this.journalFormat })}\n`;
    // KNOWN LIMITATION: A world whose encoded checkpoint exceeds the cache budget requires replay.
    if (macBytes + Buffer.byteLength(header) + data.length > maximumBytes) return;
    let key = await this.#readKey();
    if (!key) {
      key = randomBytes(macBytes);
      await publishBytes(this.keyFilename, key);
    }
    // Forked tasks can retain the same conversation. The portable encoding
    // has no heap aliases, so compress its repeated bytes before publication.
    const payload = gzipSync(Buffer.from(data, 'latin1'));
    // KNOWN LIMITATION: Compression can expand an incompressible image near the bound.
    if (macBytes + Buffer.byteLength(header) + payload.length > maximumBytes) return;
    const mac = createHmac('sha256', key).update(header).update(payload).digest();
    await publishBytes(this.filename, Buffer.concat([mac, Buffer.from(header), payload]));
  }
}
