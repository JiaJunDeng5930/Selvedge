/** Lossless JSON at the shared value boundary. Numeric lexemes survive the Bend round trip. */
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

/** Emit the tagged value tokens consumed by Bend JSON. */
export function emitJsonTokens(value, emit) {
  function token(text) {
    if (!text.isWellFormed()) throw new TypeError('JSON strings must contain Unicode scalar values');
    emit(text);
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
}

export function tokenizeJsonValue(input) {
  const tokens = [];
  emitJsonTokens(input, token => tokens.push(token));
  return tokens;
}
