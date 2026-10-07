export function bendValue(qualifiedName, fields = {}) {
  return { ...fields, $: qualifiedName };
}

export function bendTag(value) {
  return typeof value?.$ === 'string' ? value.$.slice(value.$.lastIndexOf('.') + 1) : undefined;
}

/** Validate observations against Bend's immediate Nat representation. */
export function observedNatNumber(number, name) {
  if (!Number.isSafeInteger(number) || number < 0 || number > 281474976710655) {
    throw new TypeError(`Invalid ${name}`);
  }
  return number;
}

/** Transport compiler values without maintaining a domain schema. */
export function encodeBendValue(value) {
  if (typeof value === 'bigint') return { $: '$bigint', value: value.toString() };
  if (Array.isArray(value)) return value.map(encodeBendValue);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encodeBendValue(item)]));
  }
  return value;
}

export function decodeBendValue(value) {
  if (value !== null && typeof value === 'object' && value.$ === '$bigint') {
    if (Object.keys(value).length !== 2 || typeof value.value !== 'string' || !/^-?(0|[1-9][0-9]*)$/.test(value.value)) {
      throw new TypeError('Malformed Bend integer');
    }
    return BigInt(value.value);
  }
  if (Array.isArray(value)) return value.map(decodeBendValue);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, decodeBendValue(item)]));
  }
  return value;
}
