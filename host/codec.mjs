import { parseJson, stringifyJson, safeInteger } from './public/json-tokens.mjs';

export { JsonNumber, parseJson, stringifyJson, safeInteger, naturalKey, sameNatural } from './public/json-tokens.mjs';

export function integer(value, name = 'integer') {
  const number = safeInteger(value);
  // DEFENSE: HTTP event cursors and page sizes can be fractional, negative or outside JavaScript's exact integer range.
  if (!Number.isSafeInteger(number) || number < 0) throw new TypeError(`${name} must be a nonnegative safe integer`);
  return number;
}

/** Exact JSON text is the complete extracted-program input boundary. */
export function encodeInput(value, maximum = Infinity) {
  const text = stringifyJson(value);
  // DEFENSE: Public commands and external tool results can exceed the admitted UTF-8 input budget.
  if (Buffer.byteLength(text, 'utf8') > maximum) throw new RangeError('Input exceeds the kernel frame limit');
  return text;
}

/** Copy a JSON command while preserving exact numeric lexemes. */
export const cloneJson = value => value === undefined ? undefined : parseJson(stringifyJson(value));
