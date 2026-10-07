import { Markdown } from './markdown.mjs';

export function list(value) {
  const result = [];
  while (value?.$ === 'Con') { result.push(value.head); value = value.tail; }
  if (value?.$ !== 'Nil') throw new TypeError('Expected a compiled Bend list');
  return result;
}
const svg = 'http://www.w3.org/2000/svg';
const booleans = new Set(['disabled', 'checked', 'selected', 'multiple', 'required', 'hidden', 'inert', 'readOnly', 'autofocus']);

/** Execute the document vocabulary without interpreting product roles. */
export class Renderer {
  constructor(root, callbacks, { isolated = false } = {}) {
    this.root = root;
    this.callbacks = callbacks;
    this.records = new Map();
    this.targets = new Map();
    this.composing = new WeakSet();
    this.deferred = [];
    this.document = null;
    this.generation = null;
    this.isolated = isolated;
    this.disposed = false;
  }
  target(key) {
    if (key === '@document/root') return this.isolated ? this.root : this.root.ownerDocument.documentElement;
    return this.targets.get(key) ?? this.records.get(key)?.node;
  }
  ownedTarget(key) {
    const node = this.target(key);
    if (!node || !this.root.contains(node)) throw new Error(`Missing owned native target ${key}`);
    return node;
  }
  targetBounds(key, origin) {
    if (!this.root.contains(origin)) throw new Error('Target origin is outside the renderer');
    const box = this.ownedTarget(key).getBoundingClientRect();
    const content = origin.getBoundingClientRect();
    return { left: box.left - content.left, top: box.top - content.top, width: box.width, height: box.height };
  }
  async whenSettled() {
    while (!this.disposed) {
      const instances = [...this.records.values()].flatMap(record => record.markdown ? [record.markdown] : []);
      if ((await Promise.all(instances.map(markdown => markdown.whenSettled()))).some(done => !done) || this.disposed) return false;
      // NOTE: Parser-owned anchors must exist before declarative portals and target properties can be replayed.
      if (this.document) this.render(this.document, this.generation);
      const current = [...this.records.values()].flatMap(record => record.markdown ? [record.markdown] : []);
      if (current.length === instances.length && current.every((markdown, index) => markdown === instances[index])) return true;
    }
    return false;
  }
  dispose() {
    this.disposed = true;
    for (const record of this.records.values()) record.markdown?.dispose();
    this.records.clear(); this.targets.clear(); this.document = null;
    this.root.replaceChildren();
  }
  properties(record, attributes, styles) {
    const node = record.node;
    const next = new Map(list(attributes).map(value => [value.name, value.value]));
    for (const name of record.attributes?.keys() ?? []) {
      if (!next.has(name)) {
        node.removeAttribute(name);
        if (booleans.has(name)) node[name] = false;
      }
    }
    for (const [name, value] of next) {
      if (name === 'value' && 'value' in node) continue;
      if (booleans.has(name)) {
        const enabled = value !== 'false';
        if (node[name] !== enabled) node[name] = enabled;
        if (enabled && !node.hasAttribute(name)) node.setAttribute(name, '');
        if (!enabled && node.hasAttribute(name)) node.removeAttribute(name);
      } else if (node.getAttribute(name) !== value) node.setAttribute(name, value);
    }
    const declarations = list(styles).map(value => [value.name, value.value]);
    const styleSource = JSON.stringify(declarations);
    const nextStyles = new Map(declarations);
    if (record.styleSource !== styleSource) {
      for (const name of record.styles?.keys() ?? []) if (!nextStyles.has(name)) node.style.removeProperty(name);
      // NOTE: Replay source order because normalized CSSOM values and shorthand/logical declarations interact.
      for (const [name, value] of declarations) node.style.setProperty(name, value);
      record.styleSource = styleSource;
    }
    record.attributes = next;
    record.styles = nextStyles;
  }
  replaceValue(record, value) {
    const node = record.node;
    if (!('value' in node) || node.value === value) return;
    const active = node === node.ownerDocument.activeElement;
    const selection = active && typeof node.selectionStart === 'number'
      ? [node.selectionStart, node.selectionEnd, node.selectionDirection] : null;
    node.value = value;
    if (selection) node.setSelectionRange(Math.min(selection[0], value.length), Math.min(selection[1], value.length), selection[2]);
  }
  fieldSession(record, event) {
    record.fieldSession ??= this.callbacks.fieldSessionInitial();
    const decision = this.callbacks.fieldSessionStep(event, record.fieldSession);
    record.fieldSession = decision.record;
    if (decision.replace && decision.record.canonical.$ === 'Some') this.replaceValue(record, decision.record.canonical.value);
    return decision;
  }
  controlledValue(record) {
    if (!record.attributes.has('value') || !('value' in record.node)) return;
    const value = record.attributes.get('value');
    // Isolated measurement documents have no user editing sessions.
    if (this.isolated) { this.replaceValue(record, value); return; }
    this.fieldSession(record, { $: 'Synchronize', value });
  }
  synchronizeFields(updates) {
    for (const update of list(updates)) {
      const record = this.records.get(update.key);
      if (!record || !this.root.contains(record.node)) continue;
      if (update.$ === 'SetIdentity') {
        if (!this.isolated) this.fieldSession(record, { $: 'Rebind', identity: update.identity });
      } else if (update.$ === 'SetValue') {
        record.attributes.set('value', update.value);
        this.controlledValue(record);
      } else if (update.$ === 'SetChecked') {
        if (record.node.checked !== update.checked) record.node.checked = update.checked;
        if (update.checked) { record.attributes.set('checked', 'true'); record.node.setAttribute('checked', ''); }
        else { record.attributes.delete('checked'); record.node.removeAttribute('checked'); }
      } else throw new TypeError(`Unknown native field update ${update.$}`);
    }
  }
  events(record, bindings) {
    record.bindings = list(bindings);
    if (record.bound) return;
    record.bound = true;
    const node = record.node;
    const dispatch = (kind, native) => {
      for (const event of record.bindings) if (event.$ === kind) this.callbacks.event(event, native, node, this.composing.has(node));
    };
    const session = event => this.isolated ? { deliver: false } : this.fieldSession(record, { $: event });
    node.addEventListener('compositionstart', () => { this.composing.add(node); session('CompositionStarted'); });
    node.addEventListener('compositionend', event => {
      this.composing.delete(node);
      if (session('CompositionEnded').deliver) dispatch('EditText', event);
    });
    node.addEventListener('pointerdown', () => {
      if (record.fieldSession?.session.$ === 'SupersededTail') session('InputStarted');
    });
    for (const event of ['paste', 'drop', 'cut']) node.addEventListener(event, () => session('InputStarted'));
    node.addEventListener('click', event => {
      if (node.type === 'file') session('InputStarted');
      if (record.bindings.some(binding => binding.$ === 'Activate')) event.preventDefault();
      dispatch('Activate', event); dispatch('PlaceCard', event);
    });
    node.addEventListener('keydown', event => {
      if (!event.isComposing && event.keyCode !== 229 && event.key !== 'Process') session('InputStarted');
      dispatch('ConfirmText', event);
    });
    node.addEventListener('input', event => { if (session('InputObserved').deliver) dispatch('EditText', event); });
    node.addEventListener('change', event => {
      if (!session('InputObserved').deliver) return;
      dispatch('EditToggle', event); dispatch('SelectFiles', event); dispatch('SelectDestination', event);
    });
    node.addEventListener('dragstart', event => dispatch('DragCard', event));
    node.addEventListener('dragover', event => { if (record.bindings.some(binding => binding.$ === 'DropCard')) event.preventDefault(); });
    node.addEventListener('drop', event => { event.preventDefault(); dispatch('DropCard', event); });
  }
  children(parent, values, path, namespace) {
    const expected = new Set();
    let index = 0;
    list(values).forEach((value, descriptorIndex) => {
      const node = this.node(value, `${path}/${descriptorIndex}`, namespace);
      if (!node) return;
      expected.add(node);
      // NOTE: Recursive construction can reparent siblings and invalidate a saved cursor.
      const reference = parent.childNodes[index] ?? null;
      if (node !== reference) parent.insertBefore(node, reference);
      index++;
    });
    for (const node of [...parent.childNodes]) if (!expected.has(node)) node.remove();
  }
  node(value, path, namespace) {
    if (value.$ === 'Portal' || value.$ === 'TargetProperties') { this.deferred.push(value); return null; }
    const key = value.key ?? path;
    const kind = value.$ === 'Element' ? `${namespace ?? ''}:${value.tag}` : value.$;
    let record = this.records.get(key);
    if (record && record.kind !== kind) {
      record.markdown?.dispose();
      for (const target of record.targets ?? []) this.targets.delete(target);
      record.node.remove(); this.records.delete(key); record = null;
    }
    if (!record) {
      let node;
      if (value.$ === 'Text') node = this.root.ownerDocument.createTextNode(value.value);
      else if (value.$ === 'Markdown') { node = this.root.ownerDocument.createElement('div'); node.className = 'markdown'; }
      else if (value.$ === 'Element') {
        const ns = value.tag === 'svg' ? svg : namespace;
        node = ns ? this.root.ownerDocument.createElementNS(ns, value.tag) : this.root.ownerDocument.createElement(value.tag);
      } else throw new TypeError(`Unknown document node ${value.$}`);
      record = { node, kind, key };
      this.records.set(key, record);
    }
    this.used.add(key);
    if (value.$ === 'Text') { if (record.node.data !== value.value) record.node.data = value.value; }
    else if (value.$ === 'Element') {
      this.properties(record, value.attributes, value.styles);
      this.events(record, value.events);
      this.children(record.node, value.children, key, record.node.namespaceURI === svg && value.tag !== 'foreignObject' ? svg : undefined);
      this.controlledValue(record);
    } else {
      if (value.native_owner.$ === 'Some') record.node.dataset.nativeContentOwner = value.native_owner.value;
      else delete record.node.dataset.nativeContentOwner;
      const source = value.source.$ === 'Some' ? value.source.value : null;
      const owner = source ? this.callbacks.codeKey(source, 0n) : null;
      if (!record.markdown || record.text !== value.value || record.owner !== owner) {
        record.markdown?.dispose();
        for (const target of record.targets ?? []) this.targets.delete(target);
        record.node.replaceChildren(); record.targets = [];
        // NOTE: Parsing is paced; retain the publication that supplied this parser's input.
        record.parseGeneration = this.generation;
        record.markdown = new Markdown(record.node, {
          smooth: false,
          codeKey: source ? ordinal => this.callbacks.codeKey(source, ordinal) : undefined,
          codeSource: source ? (ordinal, text) => {
            const generation = record.parseGeneration;
            if (generation !== null) this.callbacks.codeSource(source, ordinal, text, generation, record.text);
          } : undefined,
          target: (target, node) => { this.targets.set(target, node); record.targets.push(target); },
          onChange: () => this.callbacks.changed?.(),
        });
        record.text = value.value;
        record.owner = owner;
        record.markdown.append(value.value); record.markdown.finish();
      }
    }
    return record.node;
  }
  render(document, generation = null) {
    if (this.disposed) throw new Error('Renderer is disposed');
    this.document = document;
    this.generation = generation;
    this.used = new Set(); this.deferred = [];
    if (!this.isolated) this.root.ownerDocument.title = document.title;
    const node = this.node(document.root, 'root');
    if (this.root.firstChild !== node) this.root.replaceChildren(node);
    for (let index = 0; index < this.deferred.length; index++) {
      const value = this.deferred[index];
      const target = this.target(value.target);
      if (!target) continue; // Markdown anchors arrive incrementally.
      if (value.$ === 'Portal') this.children(target, value.children, value.key, target.namespaceURI === svg ? svg : undefined);
      else {
        let record = this.records.get(value.key);
        if (!record || record.node !== target) { record = { node: target, kind: 'TargetProperties', key: value.key }; this.records.set(value.key, record); }
        this.used.add(value.key); this.properties(record, value.attributes, value.styles);
        this.controlledValue(record);
      }
    }
    for (const [key, record] of this.records) if (!this.used.has(key)) {
      record.markdown?.dispose();
      for (const target of record.targets ?? []) this.targets.delete(target);
      if (record.kind !== 'TargetProperties') record.node.remove();
      this.records.delete(key);
    }
  }
}
