/** The adapter understands widget types and bindings, never agent semantics. */
export function eventForForm(form, values) {
  const event = structuredClone(form.event);
  for (const field of form.fields) {
    let value = values[field.name] ?? '';
    if (field.kind === 'integer') {
      if (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value))) throw new TypeError(`${field.label} must be an integer`);
      value = Number(value);
    } else if (field.kind === 'json') value = JSON.parse(value);
    const route = field.binding;
    if (!Array.isArray(route) || !route.length || route.some(key => typeof key !== 'string' || ['__proto__', 'prototype', 'constructor'].includes(key))) {
      throw new TypeError('Invalid widget binding');
    }
    let target = event;
    for (const key of route.slice(0, -1)) {
      if (!Object.hasOwn(target, key) || !target[key] || typeof target[key] !== 'object') throw new TypeError('Missing widget binding target');
      target = target[key];
    }
    if (!Object.hasOwn(target, route.at(-1))) throw new TypeError('Missing widget binding field');
    target[route.at(-1)] = value;
  }
  return event;
}

export { mount } from './widgets.mjs';
