import { Markdown } from './markdown.mjs';
import { MarkdownFenceObserver } from './markdown-fences.mjs';
import { stringifyJson } from './json-tokens.mjs';

const booleanProperties = new Set(['disabled', 'checked', 'selected', 'multiple', 'required', 'hidden', 'inert', 'readOnly', 'autofocus', 'open']);
const svgTags = new Set(['svg', 'path', 'line', 'polyline', 'rect', 'circle', 'text', 'g']);
const svgNamespace = 'http://www.w3.org/2000/svg';

function unmount(node) {
  if (node.nodeType === 1) {
    const dialogs = Array.from(node.querySelectorAll('dialog[open]'));
    if (node.localName === 'dialog' && node.open) dialogs.unshift(node);
    // Closing a native dialog restores its previously focused element before detachment.
    for (const dialog of dialogs) dialog.close();
  }
  node.remove();
}
function reconcile(parent, children) {
  const retained = new Set(children);
  // Remove replaced text before ordering so unchanged editor ancestors never move.
  for (const child of Array.from(parent.childNodes)) if (!retained.has(child)) unmount(child);
  let cursor = parent.firstChild;
  for (const child of children) {
    if (cursor === child) cursor = cursor.nextSibling;
    else parent.insertBefore(child, cursor);
  }
}

/** Interpret the checked document without deciding product roles or commands. */
export class Renderer {
  constructor(root, callbacks = {}, { isolated = false } = {}) {
    this.root = root;
    this.callbacks = callbacks;
    this.isolated = isolated;
    this.records = new Map();
    this.targets = new Map();
    this.composing = new WeakSet();
    this.disposed = false;
  }
  target(key) {
    return key === '@document/root' ? this.root.ownerDocument.documentElement
      : this.targets.get(key) ?? this.records.get(key)?.node;
  }
  fieldSession(record, event, value) {
    if (!this.callbacks.fieldSession || !record.attributes.has('value') || !('value' in record.node)) return { deliver: true };
    const identity = stringifyJson({ key: record.key, kind: record.metadata.kind,
      schema: record.metadata.schema, value_kind: record.metadata.value_kind,
      action: record.metadata.action, injection: record.metadata.injection, options: record.metadata.options });
    let decision;
    if (!record.fieldSession) decision = this.callbacks.fieldSession({ identity, value: record.attributes.get('value') });
    else decision = this.callbacks.fieldSession({ state: record.fieldSession, event, ...(value === undefined ? {} : { value }) });
    record.fieldSession = decision.state;
    if (decision.replace && record.node.value !== decision.state.canonical) record.node.value = decision.state.canonical;
    return decision;
  }
  properties(record, properties, styles) {
    const node = record.node;
    const next = new Map(properties.map(({ name, value }) => [name, value]));
    for (const name of record.attributes.keys()) {
      if (!next.has(name)) {
        node.removeAttribute(name);
        if (booleanProperties.has(name)) node[name] = false;
      }
    }
    for (const [name, value] of next) {
      if (name === 'value' && 'value' in node) {
        if (this.isolated && node.value !== value) node.value = value;
      } else if (booleanProperties.has(name)) {
        const enabled = value !== 'false';
        node[name] = enabled;
        if (enabled) node.setAttribute(name, ''); else node.removeAttribute(name);
      } else if (node.getAttribute(name) !== value) node.setAttribute(name, value);
    }
    const nextStyles = new Map(styles.map(({ name, value }) => [name, value]));
    for (const name of record.styles.keys()) if (!nextStyles.has(name)) node.style.removeProperty(name);
    for (const [name, value] of nextStyles) if (record.styles.get(name) !== value) node.style.setProperty(name, value);
    record.attributes = next;
    if (next.has('value') && 'value' in node && !this.isolated && this.callbacks.fieldSession) {
      const identity = stringifyJson({ key: record.key, kind: record.metadata.kind,
        schema: record.metadata.schema, value_kind: record.metadata.value_kind,
        action: record.metadata.action, injection: record.metadata.injection, options: record.metadata.options });
      if (record.fieldSession) this.fieldSession(record, 'rebind', identity);
      this.fieldSession(record, 'synchronize', next.get('value'));
    }
    record.styles = nextStyles;
  }
  listeners(record) {
    const { node } = record;
    const dispatch = (kind, event) => {
      for (const binding of record.events.filter(binding => binding.kind === kind)) {
        this.callbacks.event?.(binding, event, record.key, node, record.generation);
      }
    };
    node.addEventListener('click', event => dispatch('activate', event));
    node.addEventListener('input', event => {
      if (node.tagName === 'SELECT' || !this.fieldSession(record, 'input_observed').deliver) return;
      if (node.type === 'checkbox') dispatch('toggle', event);
      else dispatch('edit', event);
    });
    node.addEventListener('change', event => {
      if (!this.fieldSession(record, 'input_observed').deliver) return;
      if (node.tagName === 'SELECT') dispatch('edit', event);
      if (node.type === 'file') dispatch('files', event);
    });
    node.addEventListener('submit', event => { event.preventDefault(); dispatch('submit', event); });
    node.addEventListener('compositionstart', () => { this.composing.add(node); this.fieldSession(record, 'composition_started'); });
    node.addEventListener('compositionend', event => { this.composing.delete(node); if (this.fieldSession(record, 'composition_ended').deliver) dispatch('edit', event); });
    node.addEventListener('keydown', event => {
      if (!event.isComposing && event.keyCode !== 229 && event.key !== 'Process') this.fieldSession(record, 'input_started');
      this.callbacks.key?.(event, record.key, node, record);
    });
    node.addEventListener('pointerdown', event => {
      if (record.fieldSession?.session === 'superseded_tail') this.fieldSession(record, 'input_started');
      this.callbacks.reading?.('pointer', event, record.key, node);
    });
    for (const type of ['paste', 'drop', 'cut']) node.addEventListener(type, () => this.fieldSession(record, 'input_started'));
    node.addEventListener('focusin', event => this.callbacks.focus?.(event, record.key, node));
    node.addEventListener('wheel', event => this.callbacks.reading?.('scroll', event, record.key, node), { passive: true });
    node.addEventListener('touchmove', event => this.callbacks.reading?.('scroll', event, record.key, node), { passive: true });
    node.addEventListener('scroll', event => this.callbacks.reading?.('anchor', event, record.key, node), { passive: true });
    const transferredFiles = event => {
      const transfer = event.clipboardData ?? event.dataTransfer;
      return transfer && Array.from(transfer.files ?? []);
    };
    node.addEventListener('paste', event => {
      const files = transferredFiles(event);
      if (files?.length && record.events.some(binding => binding.kind === 'files')) {
        event.preventDefault(); dispatch('files', event);
      }
    });
    node.addEventListener('dragover', event => {
      if (record.events.some(binding => binding.kind === 'files')) event.preventDefault();
    });
    node.addEventListener('drop', event => {
      if (transferredFiles(event)?.length && record.events.some(binding => binding.kind === 'files')) {
        event.preventDefault(); dispatch('files', event);
      }
    });
  }
  render(document, generation = 0) {
    this.document = document;
    this.generation = generation;
    this.targets.clear();
    const used = new Set();
    const portals = [];
    const create = (value, path) => {
      if (value.kind === 'text') return this.root.ownerDocument.createTextNode(value.value);
      if (value.kind === 'portal') { portals.push({ value, path }); return null; }
      const key = value.key || path;
      used.add(key);
      let record = this.records.get(key);
      const tag = value.kind === 'markdown' ? 'div' : value.tag;
      if (record && record.tag !== tag) {
        record.markdown?.dispose(); record.fences?.dispose(); unmount(record.node); this.records.delete(key); record = null;
      }
      if (!record) {
        const node = svgTags.has(tag)
          ? this.root.ownerDocument.createElementNS(svgNamespace, tag)
          : this.root.ownerDocument.createElement(tag);
        record = { key, tag, node, attributes: new Map(), styles: new Map(), events: [], markdownTargets: new Map() };
        this.records.set(key, record);
        if (!this.isolated) this.listeners(record);
      }
      record.generation = generation;
      record.metadata = value.metadata;
      this.targets.set(key, record.node);
      if (value.kind === 'markdown') {
        record.node.className = 'markdown';
        record.metadata = value.metadata;
        if (!record.markdown || !value.value.startsWith(record.text)) {
          record.markdown?.dispose(); record.markdownTargets.clear(); record.node.replaceChildren();
          record.markdown = new Markdown(record.node, { onChange: () => this.callbacks.layout?.(),
            codeKey: ordinal => this.callbacks.codeKey?.(key, ordinal),
            codeSource: (ordinal, text) => this.callbacks.codeSource?.(key, ordinal, text),
            target: (target, node) => { record.markdownTargets.set(target, node); this.targets.set(target, node); } });
          record.text = '';
        }
        record.markdown.append(value.value.slice(record.text.length));
        record.text = value.value;
        for (const [target, node] of record.markdownTargets) this.targets.set(target, node);
        if (value.complete) record.markdown.finish();
        if (value.metadata.origin && value.metadata.epoch !== undefined && value.metadata.revision !== undefined) {
          record.fences ??= new MarkdownFenceObserver({ onFence: observed =>
            this.callbacks.fence?.(record.metadata, observed) });
          record.fences.sync({ text: value.value, epoch: stringifyJson(value.metadata.epoch),
            revision: value.metadata.revision, ending: value.metadata.ending ?? (value.complete ? 'complete' : 'open') });
        }
      } else {
        record.events = value.events.map(binding => ({ ...binding, injection: value.metadata.injection }));
        this.properties(record, value.attributes, value.styles);
        const children = value.children.map((child, index) => create(child, `${key}/${index}`)).filter(Boolean);
        // Retained native editors keep their selection and composition session.
        reconcile(record.node, children);
        if (record.tag === 'select' && record.attributes.has('value') && 'value' in record.node && !this.composing.has(record.node)
            && record.node.value !== record.attributes.get('value')) record.node.value = record.attributes.get('value');
      }
      return record.node;
    };
    const root = create(document.root, '@root');
    reconcile(this.root, [root]);
    for (const { value, path } of portals) {
      const target = this.target(value.target);
      if (target) reconcile(target, value.children.map((child, index) => create(child, `${path}/${index}`)).filter(Boolean));
    }
    for (const [key, record] of this.records) {
      if (!used.has(key)) { record.markdown?.dispose(); record.fences?.dispose(); unmount(record.node); this.records.delete(key); }
    }
    for (const record of this.records.values()) {
      if (record.tag === 'dialog' && record.node.open && !record.node.matches(':modal')) {
        record.node.open = false;
        record.node.showModal();
      }
    }
    this.root.ownerDocument.title = document.title;
  }
  restoreField(key, value) {
    const record = this.records.get(key);
    // DEFENSE: The owning scene may have removed a field before its rejection reaches the native publication.
    if (!record) return;
    this.fieldSession(record, 'reject', value);
  }
  async whenSettled() {
    const results = await Promise.all(Array.from(this.records.values(), record => record.markdown?.whenSettled() ?? true));
    return !this.disposed && results.every(Boolean);
  }
  async whenCaughtUp() {
    const results = await Promise.all(Array.from(this.records.values()).flatMap(record => [record.markdown?.whenCaughtUp() ?? true, record.fences?.whenCaughtUp() ?? true]));
    return !this.disposed && results.every(Boolean);
  }
  dispose() {
    this.disposed = true;
    for (const record of this.records.values()) { record.markdown?.dispose(); record.fences?.dispose(); }
    reconcile(this.root, []); this.records.clear(); this.targets.clear();
  }
}
