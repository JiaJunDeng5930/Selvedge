import { crc32, deflateSync } from 'node:zlib';

export const imageBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==';
export const imageBytes = Buffer.from(imageBase64, 'base64');

function chunk(kind, data) {
  const bytes = Buffer.alloc(data.length + 12);
  bytes.writeUInt32BE(data.length);
  bytes.write(kind, 4, 'ascii');
  data.copy(bytes, 8);
  bytes.writeUInt32BE(crc32(bytes.subarray(4, -4)), bytes.length - 4);
  return bytes;
}

/** A valid, incompressible 1024×1024 RGB image whose base64 exceeds the old 4 MiB frame budget. */
export function largeImageBytes() {
  const size = 1024;
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size);
  header.writeUInt32BE(size, 4);
  header[8] = 8;
  header[9] = 2;
  const rows = Buffer.alloc(size * (size * 3 + 1));
  let random = 0x79b3e246;
  for (let row = 0; row < size; row++) {
    const start = row * (size * 3 + 1);
    for (let column = 1; column <= size * 3; column++) {
      random ^= random << 13;
      random ^= random >>> 17;
      random ^= random << 5;
      rows[start + column] = random & 255;
    }
  }
  return Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', header),
    chunk('IDAT', deflateSync(rows)), chunk('IEND', Buffer.alloc(0))]);
}
