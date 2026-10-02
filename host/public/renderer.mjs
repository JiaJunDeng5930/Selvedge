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
  constructor(root, callbacks) {
    this.root = root;
    this.callbacks = callbacks;
    this.records = new Map();
    this.targets = new Map();
    this.composing = new WeakSet();
    this.deferred = [];
    this.document = null;
  }
  target(key) {
    if (key === '@document/root') return this.root.ownerDocument.documentElement;
    return this.targets.get(key) ?? this.records.get(key)?.node;
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
    const nextStyles = new Map(list(styles).map(value => [value.name, value.value]));
    for (const name of record.styles?.keys() ?? []) if (!nextStyles.has(name)) node.style.removeProperty(name);
    for (const [name, value] of nextStyles) if (node.style.getPropertyValue(name) !== value) node.style.setProperty(name, value);
    record.attributes = next;
    record.styles = nextStyles;
  }
  controlledValue(record) {
    const node = record.node;
    if (!record.attributes.has('value') || !('value' in node)) return;
    const value = record.attributes.get('value');
    // Options must exist before assigning a select value, including an empty value.
    if (node.localName === 'select') { node.value = value; return; }
    if (this.composing.has(node) || node.value === value) return;
    const active = node === node.ownerDocument.activeElement;
    const selection = active && typeof node.selectionStart === 'number'
      ? [node.selectionStart, node.selectionEnd, node.selectionDirection] : null;
    node.value = value;
    if (selection) node.setSelectionRange(Math.min(selection[0], value.length), Math.min(selection[1], value.length), selection[2]);
  }
  events(record, bindings) {
    record.bindings = list(bindings);
    if (record.bound) return;
    record.bound = true;
    const node = record.node;
    const dispatch = (kind, native) => {
      for (const event of record.bindings) if (event.$ === kind) this.callbacks.event(event, native, node);
    };
    node.addEventListener('compositionstart', () => this.composing.add(node));
    node.addEventListener('compositionend', event => { this.composing.delete(node); dispatch('EditText', event); });
    node.addEventListener('click', event => {
      if (record.bindings.some(binding => binding.$ === 'Activate')) event.preventDefault();
      dispatch('Activate', event); dispatch('PlaceCard', event);
    });
    node.addEventListener('input', event => { if (!event.isComposing) dispatch('EditText', event); });
    node.addEventListener('change', event => { dispatch('EditToggle', event); dispatch('SelectFiles', event); });
    node.addEventListener('dragstart', event => dispatch('DragCard', event));
    node.addEventListener('dragover', event => { if (record.bindings.some(binding => binding.$ === 'DropCard')) event.preventDefault(); });
    node.addEventListener('drop', event => { event.preventDefault(); dispatch('DropCard', event); });
  }
  children(parent, values, path, namespace) {
    let cursor = parent.firstChild;
    list(values).forEach((value, index) => {
      const node = this.node(value, `${path}/${index}`, namespace);
      if (!node) return;
      if (node !== cursor) parent.insertBefore(node, cursor);
      cursor = node.nextSibling;
    });
    while (cursor) { const next = cursor.nextSibling; cursor.remove(); cursor = next; }
  }
  node(value, path, namespace) {
    if (value.$ === 'Portal' || value.$ === 'TargetProperties') { this.deferred.push(value); return null; }
    const key = value.key ?? path;
    const kind = value.$ === 'Element' ? `${namespace ?? ''}:${value.tag}` : value.$;
    let record = this.records.get(key);
    if (record && record.kind !== kind) { record.markdown?.dispose(); record.node.remove(); this.records.delete(key); record = null; }
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
      if (!record.markdown || record.text !== value.value) {
        record.markdown?.dispose();
        for (const target of record.targets ?? []) this.targets.delete(target);
        record.node.replaceChildren(); record.targets = [];
        const source = value.source.$ === 'Some' ? value.source.value : null;
        record.markdown = new Markdown(record.node, {
          smooth: false,
          codeKey: source ? ordinal => this.callbacks.codeKey(source, ordinal) : undefined,
          codeSource: source ? (ordinal, text) => this.callbacks.codeSource(source, ordinal, text) : undefined,
          target: (target, node) => { this.targets.set(target, node); record.targets.push(target); },
          onChange: () => this.callbacks.changed?.(),
        });
        record.text = value.value;
        record.markdown.append(value.value); record.markdown.finish();
      }
    }
    return record.node;
  }
  render(document) {
    this.document = document;
    this.used = new Set(); this.deferred = [];
    this.root.ownerDocument.title = document.title;
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
