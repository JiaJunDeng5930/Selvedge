import { Markdown } from './markdown.mjs';
import { MarkdownFenceObserver } from './markdown-fences.mjs';
import { stringifyJson } from './json-tokens.mjs';
import { keyObservation } from './keyboard.mjs';

const booleanProperties = new Set(['disabled', 'checked', 'indeterminate', 'selected', 'multiple', 'required', 'hidden', 'inert', 'readOnly', 'autofocus', 'open']);
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
function focusVisible(node) {
  if (!node?.isConnected || node.disabled || node.closest('[inert],[hidden]')
    || !node.getClientRects().length || getComputedStyle(node).visibility === 'hidden') return false;
  const bounds = node.getBoundingClientRect();
  const viewport = node.ownerDocument.defaultView;
  return bounds.left >= 0 && bounds.top >= 0
    && bounds.right <= viewport.innerWidth && bounds.bottom <= viewport.innerHeight;
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
    this.modal = null;
    this.focusScope = [];
    this.disposed = false;
    this.anchorFocus = () => queueMicrotask(() => this.refreshAnchors());
    if (!isolated) {
      root.addEventListener('focusin', this.anchorFocus);
      root.addEventListener('focusout', this.anchorFocus);
    }
  }
  refreshNativeTargets() {
    if (this.targetRefresh || this.disposed) return;
    this.targetRefresh = true;
    queueMicrotask(() => {
      this.targetRefresh = false;
      if (!this.disposed && this.document) this.render(this.document, this.generation);
    });
  }
  target(key) {
    return key === '@document/root' ? this.root.ownerDocument.documentElement
      : this.targets.get(key) ?? this.records.get(key)?.node;
  }
  resolveTarget(key, { modal = true, fallback } = {}) {
    const scope = modal && this.modalRecord()?.node || this.root;
    const preferredView = this.root.ownerDocument.activeElement?.closest('[data-view]')?.dataset.view ?? '';
    const nodes = Array.from(scope.querySelectorAll('[data-key]')).filter(node =>
      !node.closest('[inert],[hidden]') && !node.disabled && node.getClientRects().length && getComputedStyle(node).visibility !== 'hidden');
    if (scope.dataset?.key) nodes.unshift(scope);
    const resolved = this.callbacks.resolveTarget({ target: key, view: preferredView, ...(fallback === undefined ? {} : { fallback }),
      candidates: nodes.map(node => ({ key: node.dataset.key,
        aliases: [node.dataset.logicalKey, node.dataset.focusAlias].filter(value => value !== undefined),
        view: node.dataset.view ?? '' })) });
    return resolved === null ? null : this.target(resolved);
  }
  modalRecord() {
    return this.modal?.matches(':modal') ? this.records.get(this.modal.dataset.key) : null;
  }
  refreshAnchors() {
    for (const anchor of this.root.querySelectorAll('[data-native-anchor-owner]')) anchor.removeAttribute('data-native-anchor-owner');
    for (const positioned of this.root.querySelectorAll('[data-anchor]')) {
      const anchor = this.resolveTarget(positioned.dataset.anchor, { modal: false });
      // DEFENSE: resizing can remove a trigger's responsive branch while its activity remains open.
      if (!anchor?.isConnected) {
        positioned.style.removeProperty('position-anchor');
        continue;
      }
      const name = '--selvedge-anchor-' + CSS.escape(positioned.dataset.key);
      anchor.style.anchorName = name;
      positioned.style.positionAnchor = name;
      if (positioned.dataset.anchorFocus === 'true') {
        positioned.hidden = anchor !== this.root.ownerDocument.activeElement;
        anchor.setAttribute('aria-expanded', String(!positioned.hidden));
      }
      if (!positioned.hidden) anchor.dataset.nativeAnchorOwner = 'true';
    }
  }
  fieldSession(record, event, value) {
    if (!this.callbacks.fieldSession || !record.attributes.has('value') || !('value' in record.node)) return { deliver: true };
    const identity = stringifyJson({ key: record.key, owner: record.metadata.field_session?.owner });
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
    // The document projection has already resolved appearance. Upstream token
    // aliases use :root, including content physically mounted through portals.
    if (!this.isolated && next.get('data-layout') === 'workspace' && next.has('data-theme')) {
      this.root.ownerDocument.documentElement.setAttribute('data-theme', next.get('data-theme'));
    }
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
    const styleSource = stringifyJson(styles);
    // Rebuild from an empty declaration list so CSS shorthand and logical properties keep source order.
    if (record.styleSource !== styleSource) {
      node.style.cssText = '';
      for (const { name, value } of styles) node.style.setProperty(name, value);
      record.styleSource = styleSource;
    }
    record.attributes = next;
    if (next.has('value') && 'value' in node && !this.isolated && this.callbacks.fieldSession) {
      const identity = stringifyJson({ key: record.key, owner: record.metadata.field_session?.owner });
      if (record.fieldSession) this.fieldSession(record, 'rebind', identity);
      this.fieldSession(record, 'synchronize', next.get('value'));
    }
  }
  listeners(record) {
    const { node } = record;
    const dispatch = (name, event) => {
      for (const binding of record.events.filter(binding => binding.event === name))
        this.callbacks.event?.(binding, event, record.key, node, record.generation);
    };
    node.addEventListener('click', event => dispatch('click', event));
    node.addEventListener('input', event => {
      if (!this.fieldSession(record, 'input_observed').deliver) return;
      dispatch('input', event);
    });
    node.addEventListener('change', event => {
      if (this.fieldSession(record, 'input_observed').deliver) dispatch('change', event);
    });
    node.addEventListener('submit', event => { event.preventDefault(); dispatch('submit', event); });
    node.addEventListener('cancel', event => { event.preventDefault(); dispatch('cancel', event); });
    node.addEventListener('compositionstart', () => { this.composing.add(node); this.fieldSession(record, 'composition_started'); });
    node.addEventListener('compositionend', event => {
      this.composing.delete(node);
      if (this.fieldSession(record, 'composition_ended').deliver) dispatch('input', event);
    });
    node.addEventListener('keydown', event => {
      const keyboard = this.callbacks.keyboard?.(keyObservation(event, this.composing.has(node)));
      if (keyboard?.input_started) this.fieldSession(record, 'input_started');
      for (const binding of record.events.filter(binding => binding.event === 'keydown')) {
        if (binding.kind === 'confirm' ? keyboard?.confirm : keyboard?.activate)
          this.callbacks.event?.(binding, event, record.key, node, record.generation);
      }
      this.callbacks.key?.(event, record.key, node, record, keyboard);
    });
    node.addEventListener('pointerdown', event => {
      if (node.dataset.retainFocus === 'true') event.preventDefault();
      if (record.fieldSession?.session === 'superseded_tail') this.fieldSession(record, 'input_started');
      this.callbacks.reading?.('pointer', event, record.key, node);
    });
    for (const type of ['paste', 'drop', 'cut']) node.addEventListener(type, () => this.fieldSession(record, 'input_started'));
    node.addEventListener('focusin', event => this.callbacks.focus?.(event, record.key, node));
    node.addEventListener('wheel', event => this.callbacks.reading?.('scroll', event, record.key, node), { passive: true });
    node.addEventListener('touchmove', event => this.callbacks.reading?.('scroll', event, record.key, node), { passive: true });
    node.addEventListener('scroll', event => this.callbacks.reading?.('anchor', event, record.key, node), { passive: true });
    const transferredFiles = event => Array.from((event.clipboardData ?? event.dataTransfer)?.files ?? []);
    // A pasted file targets the editor; its form's ReceiveFile control owns admission.
    const fileReceivers = () => {
      const candidates = node.form
        ? Array.from(this.records.values()).filter(candidate => candidate.node.form === node.form)
        : [record];
      return candidates.filter(candidate => !candidate.node.disabled)
        .flatMap(candidate => candidate.events.some(binding => binding.kind === 'files') ? [candidate] : []);
    };
    for (const type of ['paste', 'drop']) node.addEventListener(type, event => {
      const receivers = fileReceivers();
      if (transferredFiles(event).length && receivers.length) {
        event.preventDefault();
        for (const receiver of receivers)
          for (const binding of receiver.events.filter(binding => binding.kind === 'files'))
            this.callbacks.event?.(binding, event, receiver.key, receiver.node, receiver.generation);
      }
    });
    node.addEventListener('dragover', event => {
      if (fileReceivers().length) event.preventDefault();
    });
  }
  render(document, generation = 0) {
    const active = this.root.ownerDocument.activeElement;
    this.document = document;
    const previousScope = this.focusScope;
    this.focusScope = document.focus_scope;
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
        record = { key, tag, node, attributes: new Map(), styleSource: '', events: [], markdownTargets: new Map() };
        this.records.set(key, record);
        if (!this.isolated) this.listeners(record);
      }
      record.generation = generation;
      record.metadata = value.metadata ?? {};
      this.targets.set(key, record.node);
      if (value.kind === 'markdown') {
        record.node.className = 'markdown';
        record.metadata = value.metadata ?? {};
        if (!record.markdown || !value.value.startsWith(record.text)) {
          record.markdown?.dispose(); record.markdownTargets.clear(); record.node.replaceChildren();
          const current = () => this.records.get(key) === record;
          record.markdown = new Markdown(record.node, { onChange: () => { if (current()) this.callbacks.layout?.(); },
            ...(record.metadata.source === undefined ? {} : {
              codeIdentity: ordinal => this.callbacks.codeIdentity?.(record.metadata.source, ordinal),
              codeTargets: identity => this.callbacks.codeTargets?.(identity, record.metadata.view ?? null),
              codeSource: (ordinal, text) => { if (current()) this.callbacks.codeSource?.(record.metadata.source, ordinal, text, record.metadata.view ?? null); },
            }),
            target: (target, node) => {
              // DEFENSE: parser work may complete after its document's namespace was retired.
              if (!current()) return;
              record.markdownTargets.set(target, node); this.targets.set(target, node);
              this.refreshNativeTargets();
            } });
          record.text = '';
        }
        record.markdown.append(value.value.slice(record.text.length));
        record.text = value.value;
        for (const [target, node] of record.markdownTargets) this.targets.set(target, node);
        if (value.complete) record.markdown.finish();
        if (value.metadata.origin && value.metadata.epoch !== undefined && value.metadata.revision !== undefined) {
          record.fences ??= new MarkdownFenceObserver({ onFence: observed => {
            if (this.records.get(key) === record) this.callbacks.fence?.(record.metadata, observed);
          } });
          record.fences.sync({ text: value.value, epoch: stringifyJson(value.metadata.epoch),
            revision: value.metadata.revision, ending: value.metadata.ending ?? (value.complete ? 'complete' : 'open') });
        }
      } else {
        record.events = value.events;
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
    if (!this.isolated) {
      // DOM order is the declared layer order; retained-record insertion order can differ after resizing.
      const dialogs = Array.from(this.root.querySelectorAll('dialog[aria-modal="true"]'));
      this.refreshAnchors();
      const top = dialogs.at(-1) ?? null;
      if (this.modal !== top && this.modal?.isConnected && this.modal.matches(':modal')) {
        const previous = this.modal;
        previous.close();
        if (dialogs.includes(previous)) previous.open = true;
      }
      this.modal = top;
      if (top && !top.matches(':modal')) {
        top.open = false;
        top.showModal();
      }
      // Moving a retained header into its native drawer must not discard its focused control.
      if (active?.isConnected && active !== this.root.ownerDocument.activeElement &&
          (!top || top.contains(active)) && !active.closest('[inert]') && !active.disabled) {
        active.focus({ preventScroll: true });
      }
    }
    const updatedTargets = new Set();
    for (const update of document.target_updates) {
      const target = this.target(update.target);
      if (!target) continue;
      updatedTargets.add(target);
      const retained = this.targetProperties ??= new WeakMap();
      const previous = retained.get(target) ?? { attributes: [], styles: [] };
      for (const name of previous.attributes) if (!update.attributes.some(value => value.name === name)) target.removeAttribute(name);
      for (const name of previous.styles) if (!update.styles.some(value => value.name === name)) target.style.removeProperty(name);
      for (const { name, value } of update.attributes) target.setAttribute(name, value);
      for (const { name, value } of update.styles) target.style.setProperty(name, value);
      retained.set(target, { attributes: update.attributes.map(value => value.name), styles: update.styles.map(value => value.name) });
    }
    for (const target of this.updatedTargets ?? []) if (!updatedTargets.has(target)) {
      const previous = this.targetProperties.get(target);
      for (const name of previous.attributes) target.removeAttribute(name);
      for (const name of previous.styles) target.style.removeProperty(name);
      this.targetProperties.delete(target);
    }
    this.updatedTargets = updatedTargets;
    for (const record of this.records.values()) if (record.metadata.code)
      this.callbacks.codePublication?.(record.metadata.code);
    if (!this.isolated) {
      const eligible = focusVisible(active) && (!this.modal || this.modal.contains(active));
      const focus = this.callbacks.focusPlan?.({ previous: previousScope, current: this.focusScope, eligible });
      if (focus) {
        const target = this.resolveTarget(focus.target, { fallback: focus.fallback });
        const container = this.modalRecord()?.node;
        const recoveringContainer = target === container && focus.target === container?.dataset.key;
        const canFocusContainer = target?.matches('dialog') && target.hasAttribute('tabindex') && focusVisible(target);
        if (target && (!recoveringContainer || canFocusContainer)) target.focus({ preventScroll: true });
      }
    }
    if (document.title) this.root.ownerDocument.title = document.title;
  }
  restoreField(key, value) {
    const target = this.resolveTarget(key, { modal: false });
    const record = target && this.records.get(target.dataset.key);
    // DEFENSE: The owning surface may have removed a field before its rejection reaches the native publication.
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
  reset() {
    for (const record of this.records.values()) { record.markdown?.dispose(); record.fences?.dispose(); }
    reconcile(this.root, []); this.records.clear(); this.targets.clear(); this.modal = null;
    this.document = null; this.focusScope = []; this.updatedTargets = new Set(); this.targetProperties = new WeakMap();
  }
  dispose() {
    this.root.removeEventListener('focusin', this.anchorFocus);
    this.root.removeEventListener('focusout', this.anchorFocus);
    this.disposed = true;
    this.reset();
  }
}
