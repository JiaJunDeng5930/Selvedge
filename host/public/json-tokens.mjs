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
    // DEFENSE: Native numerical observations such as resource usage can be non-finite; JSON must not silently turn them into null.
    if (typeof item === 'number' && !Number.isFinite(item)) throw new TypeError('Non-finite JSON number');
    return item;
  });
}

