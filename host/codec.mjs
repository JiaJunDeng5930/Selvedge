/** Lossless JSON at the host boundary. Numeric lexemes survive the Bend round trip. */
export class JsonNumber {
  constructor(source) {
    if (typeof source !== 'string' || !/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/.test(source)) {
      throw new TypeError('Invalid JSON number');
    }
    this.source = source;
    Object.freeze(this);
  }

  toJSON() { return JSON.rawJSON(this.source); }
}

export function parseJson(text) {
  return JSON.parse(text, (_key, value, context) => {
    if (typeof value === 'number' && JSON.stringify(value) !== context.source) {
      return new JsonNumber(context.source);
    }
    return value;
  });
}

export function stringifyJson(value) {
  return JSON.stringify(value, (_key, item) => {
    if (typeof item === 'bigint') return JSON.rawJSON(item.toString());
    if (typeof item === 'number' && !Number.isFinite(item)) throw new TypeError('Non-finite JSON number');
    return item;
  });
}

export function integer(value, name = 'integer') {
  const number = value instanceof JsonNumber ? Number(value.source) : value;
  if (!Number.isSafeInteger(number) || number < 0) throw new TypeError(`${name} must be a nonnegative safe integer`);
  return number;
}

function utf8(text) {
  if (!text.isWellFormed()) throw new TypeError('JSON strings must contain Unicode scalar values');
  return Buffer.from(text, 'utf8');
}

export function encodeFrame(value, maximum = Infinity) {
  const chunks = [];
  let size = 0;
  function token(text) {
    const bytes = utf8(text);
    size += 4 + bytes.length;
    if (size > maximum || size > 0xffffffff) throw new RangeError('Input exceeds the kernel frame limit');
    const length = Buffer.allocUnsafe(4);
    length.writeUInt32BE(bytes.length);
    chunks.push(length, bytes);
  }
  function visit(item, depth) {
    if (depth > 256) throw new RangeError('JSON nesting exceeds 256 containers');
    if (item === null) return token('z');
    if (item instanceof JsonNumber) return token(`n${item.source}`);
    if (typeof item === 'bigint') return token(`n${item}`);
    if (typeof item === 'string') return token(`s${item}`);
    if (typeof item === 'boolean') return token(item ? 't' : 'f');
    if (typeof item === 'number') {
      if (!Number.isFinite(item)) throw new TypeError('Non-finite JSON number');
      return token(`n${Object.is(item, -0) ? '-0' : item}`);
    }
    if (Array.isArray(item)) {
      token('[');
      for (const element of item) visit(element, depth + 1);
      return token(']');
    }
    if (typeof item !== 'object' || ![Object.prototype, null].includes(Object.getPrototypeOf(item))) {
      throw new TypeError('Expected a JSON value');
    }
    token('{');
    for (const [key, element] of Object.entries(item)) {
      if (element === undefined) continue;
      token(`s${key}`);
      visit(element, depth + 1);
    }
    token('}');
  }
  visit(value, 0);
  const header = Buffer.allocUnsafe(4);
  header.writeUInt32BE(size);
  return Buffer.concat([header, ...chunks], size + 4);
}
