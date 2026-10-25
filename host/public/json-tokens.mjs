/** Lossless JSON at the shared value boundary. Numeric lexemes survive the extraction boundary. */
export class JsonNumber {
  constructor(source) {
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
    if (Object.is(item, -0)) return JSON.rawJSON('-0');
    // DEFENSE: Native numerical observations such as resource usage can be non-finite; JSON must not silently turn them into null.
    if (typeof item === 'number' && !Number.isFinite(item)) throw new TypeError('Non-finite JSON number');
    return item;
  });
}

/** Decode bounded wire integers by their mathematical value, without rounding. */
export function safeInteger(value) {
  if (typeof value === 'number') return Number.isSafeInteger(value) ? value : undefined;
  if (!(value instanceof JsonNumber)) return undefined;
  const match = /^(-?)(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$/.exec(value.source);
  if (!match) return undefined;
  let coefficient = (match[2] + (match[3] ?? '')).replace(/^0+/, '');
  if (!coefficient) return 0;
  const exponent = (match[4] ?? '0').replace(/^\+/, '');
  const magnitude = exponent.replace(/^-/, '').replace(/^0+/, '');
  // DEFENSE: An external JSON exponent can have millions of digits; bound it before numeric conversion or allocation.
  const limit = coefficient.length + 16;
  if (magnitude.length > String(limit).length || Number(magnitude) > limit) return undefined;
  const shift = Number(exponent) - (match[3]?.length ?? 0);
  if (shift < 0) {
    if (-shift >= coefficient.length || !coefficient.endsWith('0'.repeat(-shift))) return undefined;
    coefficient = coefficient.slice(0, shift);
  } else {
    if (coefficient.length + shift > 16) return undefined;
    coefficient += '0'.repeat(shift);
  }
  const result = Number(match[1] + coefficient);
  return Number.isSafeInteger(result) ? result : undefined;
}

/** Domain naturals use canonical decimal tokens; unlike wire integers their lexical contract is strict. */
export function naturalKey(value) {
  const token = value instanceof JsonNumber ? value.source : typeof value === 'number' && Number.isSafeInteger(value) ? String(value) : '';
  if (!/^(0|[1-9]\d*)$/.test(token)) throw new TypeError('Expected a canonical domain natural');
  return token;
}

export const sameNatural = (left, right) => naturalKey(left) === naturalKey(right);

