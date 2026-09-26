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

export function mount(root, tree, dispatch, { drafts = new Map(), disclosures = new Map() } = {}) {
  const document = root.ownerDocument;
  const focused = document.activeElement;
  const focus = focused?.id ? { id: focused.id, start: focused.selectionStart, end: focused.selectionEnd } : null;
  const element = (tag, text) => {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    return node;
  };

  function render(model, parent = '') {
    const key = `${parent}/${model.key}`;
    let node;
    if (model.kind === 'group') {
      node = element(model.role === 'details' ? 'details' : model.role === 'navigation' ? 'nav' : 'section');
      node.dataset.role = model.role;
      if (model.title) node.append(element(model.role === 'details' ? 'summary' : 'h2', model.title));
      if (model.role === 'details') {
        node.open = disclosures.get(key) ?? false;
        node.addEventListener('toggle', () => disclosures.set(key, node.open));
      }
      for (const child of model.children) node.append(render(child, key));
    } else if (model.kind === 'text') {
      node = element('article');
      node.dataset.role = model.role;
      node.append(element('h3', model.title), element('div', model.text));
    } else if (model.kind === 'value') {
      node = element('details');
      node.open = disclosures.get(key) ?? false;
      node.addEventListener('toggle', () => disclosures.set(key, node.open));
      node.append(element('summary', model.title), element('pre', JSON.stringify(model.value, null, 2)));
    } else if (model.kind === 'action') {
      node = element('button', model.label);
      node.type = 'button';
      node.disabled = !model.enabled;
      node.setAttribute('aria-current', String(model.selected));
      node.onclick = () => { if (model.enabled) dispatch(structuredClone(model.event)); };
    } else if (model.kind === 'form') {
      node = element('form');
      node.append(element('h3', model.title));
      const fields = element('fieldset');
      fields.disabled = !model.enabled;
      const inputs = new Map();
      for (const field of model.fields) {
        const inputKey = `${key}/${field.name}`;
        const label = element('label');
        label.append(element('span', field.label));
        let input;
        if (field.kind === 'choice') {
          input = element('select');
          for (const choice of field.choices) {
            const option = element('option', choice.label);
            option.value = choice.value;
            input.append(option);
          }
        } else if (['multiline', 'json'].includes(field.kind)) {
          input = element('textarea');
          input.rows = 4;
        } else if (['integer', 'text'].includes(field.kind)) {
          input = element('input');
          input.type = field.kind === 'integer' ? 'number' : 'text';
          if (field.kind === 'integer') {
            input.step = '1';
            if (field.schema.minimum !== undefined) input.min = String(field.schema.minimum);
            if (field.schema.maximum !== undefined) input.max = String(field.schema.maximum);
          }
        } else throw new TypeError(`Unsupported field kind: ${field.kind}`);
        input.id = encodeURIComponent(inputKey);
        input.name = field.name;
        input.required = field.required;
        input.value = drafts.get(inputKey) ?? (field.kind === 'json' ? JSON.stringify(field.value) : String(field.value ?? ''));
        input.addEventListener('input', () => drafts.set(inputKey, input.value));
        inputs.set(field.name, input);
        label.append(input);
        fields.append(label);
      }
      const button = element('button', model.label);
      button.type = 'submit';
      fields.append(button);
      node.append(fields);
      const error = element('p');
      error.setAttribute('role', 'alert');
      node.append(error);
      node.onsubmit = async submit => {
        submit.preventDefault();
        if (!model.enabled || button.disabled) return;
        try {
          const event = eventForForm(model, Object.fromEntries([...inputs].map(([name, input]) => [name, input.value])));
          button.disabled = true;
          await dispatch(event, key);
          error.textContent = '';
        } catch (failure) { error.textContent = failure.message; }
        finally { button.disabled = false; }
      };
    } else throw new TypeError(`Unsupported presentation node: ${model.kind}`);
    node.dataset.key = key;
    return node;
  }

  const surface = render(tree);
  root.replaceChildren(surface);
  if (focus) {
    const target = document.getElementById(focus.id);
    target?.focus({ preventScroll: true });
    if (target && ['text', 'textarea'].includes(target.type) && focus.start !== null) target.setSelectionRange(focus.start, focus.end);
  }
}
