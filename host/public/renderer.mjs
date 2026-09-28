/** The adapter understands widget types and bindings, never agent semantics. */
function bind(event, route, value) {
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
  return event;
}

export function eventForChange(change, value) {
  return bind(structuredClone(change.event), change.binding, value);
}

/** Fill only the native target binding in the native source action. */
export function eventForDrop(source, target) {
  const action = source.drops?.[target.source];
  if (!source.draggable || !action?.enabled) throw new TypeError('This item cannot be dropped here');
  const event = structuredClone(action.event);
  for (const field of target.bindings ?? []) bind(event, field.binding, field.value);
  return event;
}

export function eventForForm(form, values) {
  const event = structuredClone(form.event);
  for (const field of form.fields) {
    if (field.enabled === false) continue;
    let value = values[field.name] ?? '';
    if (field.kind === 'integer' || field.kind === 'integer-choice') {
      if (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value))) throw new TypeError(`${field.label} must be an integer`);
      value = Number(value);
    } else if (['json', 'tags', 'attachments', 'workspace'].includes(field.kind)) value = JSON.parse(value);
    else if (field.kind === 'boolean') {
      if (!['true', 'false'].includes(value)) throw new TypeError(`${field.label} must be a boolean`);
      value = value === 'true';
    }
    bind(event, field.binding, value);
  }
  return event;
}

export { mount } from './widgets.mjs';
