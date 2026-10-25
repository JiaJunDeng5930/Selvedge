import { boundary } from './model-boundary.mjs';

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
  const lexeme = value instanceof JsonNumber ? value.source
    : typeof value === 'number' ? Object.is(value, -0) ? '-0' : String(value)
    : undefined;
  if (lexeme === undefined) return undefined;
  const decoded = boundary('control.remote.safe_integer', lexeme);
  return decoded === null ? undefined : Number(decoded);
}

/** Domain naturals use canonical decimal tokens; unlike wire integers their lexical contract is strict. */
export function naturalKey(value) {
  const token = value instanceof JsonNumber ? value.source : typeof value === 'number' && Number.isSafeInteger(value) ? String(value) : '';
  if (!/^(0|[1-9]\d*)$/.test(token)) throw new TypeError('Expected a canonical domain natural');
  return token;
}

export const sameNatural = (left, right) => naturalKey(left) === naturalKey(right);

