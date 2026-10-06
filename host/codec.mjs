import { JsonNumber, emitJsonTokens } from './public/json-tokens.mjs';

export { JsonNumber, parseJson, stringifyJson } from './public/json-tokens.mjs';

export function integer(value, name = 'integer') {
  const number = value instanceof JsonNumber ? Number(value.source) : value;
  if (!Number.isSafeInteger(number) || number < 0) throw new TypeError(`${name} must be a nonnegative safe integer`);
  return number;
}

export function encodeFrame(value, maximum = Infinity) {
  const chunks = [];
  let size = 0;
  function token(text) {
    const bytes = Buffer.from(text, 'utf8');
    size += 4 + bytes.length;
    if (size > maximum || size > 0xffffffff) throw new RangeError('Input exceeds the kernel frame limit');
    const length = Buffer.allocUnsafe(4);
    length.writeUInt32BE(bytes.length);
    chunks.push(length, bytes);
  }
  emitJsonTokens(value, token);
  const header = Buffer.allocUnsafe(4);
  header.writeUInt32BE(size);
  return Buffer.concat([header, ...chunks], size + 4);
}
