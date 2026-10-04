// Convert already parsed JSON into the token vocabulary consumed by Bend JSON.
export function tokenizeJsonValue(input) {
  const tokens = [];
  function append(item) {
    if (item === null || typeof item === 'boolean' || typeof item === 'string') {
      tokens.push(JSON.stringify(item));
    } else if (typeof item === 'number' && Number.isFinite(item)) {
      tokens.push(JSON.stringify(item));
    } else if (Array.isArray(item)) {
      tokens.push('[');
      item.forEach((child, index) => { if (index) tokens.push(','); append(child); });
      tokens.push(']');
    } else if (item && typeof item === 'object' && Object.getPrototypeOf(item) === Object.prototype) {
      tokens.push('{');
      Object.entries(item).forEach(([key, child], index) => {
        if (index) tokens.push(',');
        tokens.push(JSON.stringify(key), ':');
        append(child);
      });
      tokens.push('}');
    } else throw new TypeError('Expected a parsed JSON value');
  }
  append(input);
  return tokens;
}
