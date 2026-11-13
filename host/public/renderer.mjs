import { Markdown } from './markdown.mjs';
import { MarkdownFenceObserver } from './markdown-fences.mjs';
import { stringifyJson } from './json-tokens.mjs';
import { keyObservation, applyByteSelection } from './keyboard.mjs';
import { revealAndFocus } from './layout-reveal.mjs';

const booleanProperties = new Set(['disabled', 'checked', 'indeterminate', 'selected', 'multiple', 'required', 'hidden', 'inert', 'readOnly', 'autofocus', 'open']);
const svgTags = new Set(['svg', 'path', 'line', 'polyline', 'rect', 'circle', 'text', 'g']);
const svgNamespace = 'http://www.w3.org/2000/svg';
const listenerGroup = { keyboardFocus: 1, actions: 2, field: 4, pointer: 8, reading: 16, files: 32 };

function unmount(node) {
  if (node.nodeType === 1) {
    const dialogs = Array.from(node.querySelectorAll('dialog[open]'));
    if (node.localName === 'dialog' && node.open) dialogs.unshift(node);
    // Closing a native dialog restores its previously focused element before detachment.
    for (const dialog of dialogs) dialog.close();
  }
  node.remove();
}
export function filesFromEvent(event, node) {
  const transfer = event.clipboardData ?? event.dataTransfer;
  const files = Array.from(transfer?.files ?? node?.files ?? []);
  return files.length || !transfer ? files : Array.from(transfer.items ?? [])
    .flatMap(item => item.kind === 'file' ? [item.getAsFile()].filter(Boolean) : []);
}
function replaceNativeValue(node, value) {
  const start = node.selectionStart, end = node.selectionEnd, direction = node.selectionDirection;
  node.value = value;
  if (start !== null && start !== undefined) node.setSelectionRange(start, end, direction);
}
function focusAvailable(node) {
  if (!node?.isConnected || node.disabled || node.matches('[aria-disabled="true"]') || node.closest('[inert],[hidden]')
    || !node.getClientRects().length || getComputedStyle(node).visibility === 'hidden') return false;
  return true;
}
// Clipping needs positive exposure; focus bounds must also fit the viewport.
function focusVisible(node) {
  if (!node?.isConnected) return false;
  const bounds = node.getBoundingClientRect();
  const view = node.ownerDocument.defaultView;
  const hasArea = box => box.right > box.left && box.bottom > box.top;
  let painted = hasArea(bounds);
  if (node.checkVisibility) painted &&= node.checkVisibility({ opacityProperty: true, visibilityProperty: true, contentVisibilityAuto: true });
  const intersection = { left: Math.max(0, bounds.left), top: Math.max(0, bounds.top),
    right: Math.min(view.innerWidth, bounds.right), bottom: Math.min(view.innerHeight, bounds.bottom) };
  for (let ancestor = node; ancestor; ancestor = ancestor.parentElement) {
    const style = getComputedStyle(ancestor);
    if (ancestor.hidden || style.display === 'none' || ['hidden', 'collapse'].includes(style.visibility)
      || style.contentVisibility === 'hidden' || Number(style.opacity) === 0) painted = false;
    if (ancestor === node) continue;
    const box = ancestor.getBoundingClientRect();
    if (style.overflowX !== 'visible') {
      intersection.left = Math.max(intersection.left, box.left + ancestor.clientLeft);
      intersection.right = Math.min(intersection.right, box.left + ancestor.clientLeft + ancestor.clientWidth);
    }
    if (style.overflowY !== 'visible') {
      intersection.top = Math.max(intersection.top, box.top + ancestor.clientTop);
      intersection.bottom = Math.min(intersection.bottom, box.top + ancestor.clientTop + ancestor.clientHeight);
    }
  }
  return painted && hasArea(intersection) && bounds.left >= 0 && bounds.top >= 0
    && bounds.right <= view.innerWidth && bounds.bottom <= view.innerHeight;
}
function reconcile(parent, children) {
  const current = parent.childNodes;
  if (children.length === current.length && children.every((child, index) => child === current[index])) return;
  if (current.length === 0 && children.length <= 32) { parent.append(...children); return; }
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
    this.markdownRecords = new Set();
    this.prefixFields = new Set();
    this.prefixActions = new Set();
    this.styleTexts = new Map();
    this.menuCssConfinement = new WeakMap();
    this.resizeMenus = () => { this.menuCssConfinement = new WeakMap(); };
    this.composing = new WeakSet();
    this.modal = null;
    this.focusScope = [];
    this.disposed = false;
    this.anchorFocus = event => {
      if (event.type === 'focusin' && !this.applyingFocus) this.pendingFocus = null;
      if (this.anchorRefresh) return;
      this.anchorRefresh = true;
      queueMicrotask(() => {
        this.anchorRefresh = false;
        if (!this.disposed) this.refreshAnchors();
      });
    };
    if (!isolated) {
      root.ownerDocument.defaultView.addEventListener('resize', this.resizeMenus);
      root.addEventListener('focusin', this.anchorFocus);
      root.addEventListener('focusout', this.anchorFocus);
    }
  }
  refreshNativeTargets() {
    if (this.targetRefresh || this.disposed) return;
    this.targetRefresh = true;
    queueMicrotask(() => {
      this.targetRefresh = false;
      if (this.disposed || !this.document) return;
      // A portal's new target may need its children mounted.
      if (this.hasPortals) {
        this.render(this.document, this.generation);
        this.callbacks.layout?.();
        return;
      }
      for (const [key, node] of this.targets) if (!node.isConnected) this.targets.delete(key);
      this.refreshLinks();
      if (!this.isolated) this.refreshAnchors();
      this.applyTargetUpdates(this.document);
      this.applyFocus(this.focusScope, this.focusedKey());
    });
  }
  target(key) {
    return key === '@document/root' ? this.root.ownerDocument.documentElement
      : this.targets.get(key) ?? this.records.get(key)?.node;
  }
  resolveTarget(key, { modal = true, fallback, recoverMissing = false } = {}) {
    const scope = modal && this.modalRecord()?.node || this.root;
    const preferredView = this.root.ownerDocument.activeElement?.closest('[data-view]')?.dataset.view ?? '';
    const control = 'button,input,select,textarea,a[href],[tabindex]';
    const exact = this.target(key);
    // Focus.resolve gives a live physical key precedence over all aliases.
    if (exact?.dataset.key === key && scope.contains(exact) && exact.matches(control) && focusAvailable(exact)) return exact;
    const requested = new Set(fallback === undefined ? [key] : [key, fallback]);
    const nodes = Array.from(scope.querySelectorAll('[data-key]')).filter(node => {
      const { key, logicalKey, focusAlias } = node.dataset;
      return (recoverMissing || requested.has(key) || requested.has(logicalKey) || requested.has(focusAlias)) &&
        node.matches(control) && focusAvailable(node);
    });
    if (scope.dataset?.key && focusAvailable(scope) && scope.hasAttribute('tabindex')) nodes.unshift(scope);
    const resolved = this.callbacks.resolveTarget({ target: key, view: preferredView, recover_missing: recoverMissing, ...(fallback === undefined ? {} : { fallback }),
      candidates: nodes.map(node => ({ key: node.dataset.key,
        aliases: [node.dataset.logicalKey, node.dataset.focusAlias].filter(value => value !== undefined),
        view: node.closest('[data-view]')?.dataset.view ?? '', sequential: node.tabIndex >= 0 })) });
    return resolved === null ? null : this.target(resolved);
  }
  modalRecord() {
    return this.modal?.matches(':modal') ? this.records.get(this.modal.dataset.key) : null;
  }
  confineAnchoredLayers() {
    const view = this.root.ownerDocument.defaultView;
    let width, height;
    for (const menu of this.root.querySelectorAll('[data-native-layer="menu"], [data-native-layer="anchored-dialog"]')) {
      if (menu.style.translate) menu.style.removeProperty('translate');
      // Fixed menus declare confinement through a viewport media rule. Their
      // contents can change without forcing another layout to read that rule.
      let css = this.menuCssConfinement.get(menu);
      if (!css || css.semanticKey !== menu.dataset.semanticKey) {
        css = { semanticKey: menu.dataset.semanticKey,
          confined: view.getComputedStyle(menu).getPropertyValue('--menu-css-confined') === '1' };
        this.menuCssConfinement.set(menu, css);
      }
      if (css.confined) continue;
      width ??= Math.min(view.innerWidth, view.visualViewport?.width ?? view.innerWidth);
      height ??= Math.min(view.innerHeight, view.visualViewport?.height ?? view.innerHeight);
      const bounds = menu.getBoundingClientRect();
      if (!bounds.width || !bounds.height) continue;
      const clearance = Number.parseFloat(menu.style.getPropertyValue('--layer-clearance'));
      // An in-bounds box needs no corrective transform or second layout pass.
      if (bounds.left >= clearance && bounds.top >= clearance &&
          bounds.right <= width - clearance && bounds.bottom <= height - clearance) continue;
      menu.style.translate = this.callbacks.menuGeometry(bounds);
    }
  }
  refreshAnchors() {
    const previous = new Set(this.root.querySelectorAll('[data-native-anchor-owner]'));
    for (const positioned of this.root.querySelectorAll('[data-anchor]')) {
      const key = positioned.dataset.anchor;
      const physical = this.target(key);
      // A mounted physical anchor can position a layer while its control is
      // inert behind that layer. Alias recovery still uses observed targets.
      const anchor = physical?.isConnected && physical.dataset.key === key && !physical.closest('[hidden]')
        ? physical : this.resolveTarget(key, { modal: false });
      const available = String(Boolean(anchor?.isConnected));
      if (positioned.dataset.anchorAvailable !== available) positioned.dataset.anchorAvailable = available;
      // DEFENSE: resizing can remove a trigger's responsive branch while its activity remains open.
      if (!anchor?.isConnected) {
        positioned.style.removeProperty('position-anchor');
        continue;
      }
      const name = '--selvedge-anchor-' + CSS.escape(anchor.dataset.key);
      if (anchor.style.anchorName !== name) anchor.style.anchorName = name;
      if (positioned.style.positionAnchor !== name) positioned.style.positionAnchor = name;
      if (positioned.dataset.anchorFocus === 'true') {
        const hidden = anchor !== this.root.ownerDocument.activeElement;
        if (positioned.hidden !== hidden) positioned.hidden = hidden;
        if (anchor.getAttribute('aria-expanded') !== String(!hidden)) anchor.setAttribute('aria-expanded', String(!hidden));
      }
      if (!positioned.hidden) {
        previous.delete(anchor);
        if (anchor.dataset.nativeAnchorOwner !== 'true') anchor.dataset.nativeAnchorOwner = 'true';
      }
    }
    for (const anchor of previous) anchor.removeAttribute('data-native-anchor-owner');
  }
  fieldSession(record, event, value) {
    if (!this.callbacks.fieldSession || !record.attributes.has('value') || !('value' in record.node)) return { deliver: true };
    let decision;
    if (!record.fieldSession) {
      const identity = stringifyJson({ key: record.key, owner: record.metadata.field_session?.owner });
      decision = this.callbacks.fieldSession({ identity, value: record.attributes.get('value') });
    }
    else decision = this.callbacks.fieldSession({ state: record.fieldSession, event, ...(value === undefined ? {} : { value }) });
    record.fieldSession = decision.state;
    if (decision.replace && record.node.value !== decision.state.canonical) replaceNativeValue(record.node, decision.state.canonical);
    return decision;
  }
  properties(record, properties, styles) {
    const node = record.node;
    const next = new Map(properties.map(({ name, value }) => [name, value]));
    // The document projection has already resolved appearance. Upstream token
    // aliases use :root, including content physically mounted through portals.
    if (!this.isolated && next.get('data-layout') === 'workspace' && next.has('data-theme')) {
      const root = this.root.ownerDocument.documentElement;
      if (root.getAttribute('data-theme') !== next.get('data-theme')) root.setAttribute('data-theme', next.get('data-theme'));
    }
    for (const name of record.attributes.keys()) {
      if (!next.has(name)) {
        node.removeAttribute(name);
        if (booleanProperties.has(name)) node[name] = false;
      }
    }
    for (const [name, value] of next) {
      if (name === 'value' && 'value' in node) {
        if (node.localName === 'option' && node.getAttribute(name) !== value) node.setAttribute(name, value);
        else if (this.isolated && node.value !== value) node.value = value;
      } else if (booleanProperties.has(name)) {
        const enabled = value !== 'false';
        if (node[name] !== enabled) node[name] = enabled;
        if (node.hasAttribute(name) !== enabled) {
          if (enabled) node.setAttribute(name, ''); else node.removeAttribute(name);
        }
      } else if (record.attributes.get(name) !== value && node.getAttribute(name) !== value) node.setAttribute(name, value);
    }
    const previousStyles = record.styles;
    // Rebuild from an empty declaration list so CSS shorthand and logical properties keep source order.
    if (styles.length !== previousStyles.length ||
        styles.some(({ name, value }, index) => name !== previousStyles[index].name || value !== previousStyles[index].value)) {
      const signature = JSON.stringify(styles);
      const cached = this.styleTexts.get(signature);
      if (cached !== undefined) node.style.cssText = cached;
      else {
        node.style.cssText = '';
        for (const { name, value } of styles) node.style.setProperty(name, value);
        // Store the browser's normalized declaration rather than concatenating
        // values into CSS source. Catalog rows often share these declarations.
        if (this.styleTexts.size === 128) this.styleTexts.delete(this.styleTexts.keys().next().value);
        this.styleTexts.set(signature, node.style.cssText);
      }
      record.styles = styles;
    }
    if (next.has('data-prefix-field')) this.prefixFields.add(node);
    else if (record.attributes.has('data-prefix-field')) {
      this.prefixFields.delete(node);
      node.inert = next.has('inert') && next.get('inert') !== 'false';
    }
    if (next.has('data-prefix-action')) this.prefixActions.add(record);
    else if (record.attributes.has('data-prefix-action')) {
      this.prefixActions.delete(record);
      if (!next.has('aria-disabled')) node.removeAttribute('aria-disabled');
    }
    record.attributes = next;
    if (next.has('value') && 'value' in node && !this.isolated && this.callbacks.fieldSession) {
      const identity = stringifyJson({ key: record.key, owner: record.metadata.field_session?.owner });
      const initialize = !record.fieldSession || record.fieldSession.identity !== identity;
      // Equal bindings and values are identity transitions in FieldSession.
      if (initialize && record.fieldSession) this.fieldSession(record, 'rebind', identity);
      if (!record.fieldSession || record.fieldSession.canonical !== next.get('value'))
        this.fieldSession(record, 'synchronize', next.get('value'));
      if (initialize && record.metadata.selection) {
        const { start, end, direction } = record.metadata.selection;
        applyByteSelection(node, start, end, direction, false);
      }
    }
  }
  listeners(record) {
    const { node } = record;
    const field = record.tag === 'input' || record.tag === 'textarea' || record.tag === 'select';
    const reading = record.attributes.has('data-reading-root');
    const actions = record.events.length !== 0 || record.tag === 'form' || record.tag === 'dialog';
    const files = field || record.tag === 'button' || record.tag === 'fieldset' || record.tag === 'output' ||
      record.tag === 'object' || record.events.some(binding => binding.kind === 'files');
    const groups = listenerGroup.keyboardFocus | (actions ? listenerGroup.actions : 0) |
      (field ? listenerGroup.field : 0) |
      (field || reading || record.attributes.has('data-retain-focus') ? listenerGroup.pointer : 0) |
      (reading ? listenerGroup.reading : 0) | (files ? listenerGroup.files : 0);
    const added = groups & ~record.listenerGroups;
    if (!added) return;
    record.listenerGroups |= groups;
    const deliver = (binding, event, receiver = record) => {
      const generation = receiver.generation;
      if (generation === null) return;
      this.callbacks.event?.({ ...binding, action: this.input(receiver, binding.action) },
        event, receiver.key, receiver.node, generation);
    };
    const dispatch = (name, event) => {
      for (const binding of record.events.filter(binding => binding.event === name))
        deliver(binding, event);
    };
    if (added & listenerGroup.actions) {
      node.addEventListener('click', event => dispatch('click', event));
      node.addEventListener('input', event => {
        if (!record.events.some(binding => binding.event === 'input')) return;
        if (!this.fieldSession(record, 'input_observed').deliver) return;
        dispatch('input', event);
      });
      node.addEventListener('change', event => {
        if (this.fieldSession(record, 'input_observed').deliver) dispatch('change', event);
      });
      node.addEventListener('submit', event => { event.preventDefault(); dispatch('submit', event); });
      node.addEventListener('cancel', event => { event.preventDefault(); dispatch('cancel', event); });
    }
    if (added & listenerGroup.field) {
      node.addEventListener('compositionstart', event => {
        this.composing.add(node); this.fieldSession(record, 'composition_started');
        this.callbacks.composition?.(event, record.key, node);
      });
      node.addEventListener('compositionend', event => {
        this.composing.delete(node);
        if (this.fieldSession(record, 'composition_ended').deliver) dispatch('input', event);
      });
      for (const type of ['paste', 'drop', 'cut']) node.addEventListener(type, () => this.fieldSession(record, 'input_started'));
    }
    if (added & listenerGroup.keyboardFocus) node.addEventListener('keydown', event => {
      if (event.defaultPrevented) return;
      const keyboard = this.callbacks.keyboard?.(keyObservation(event, this.composing.has(node)));
      if (keyboard?.input_started) this.fieldSession(record, 'input_started');
      for (const binding of record.events.filter(binding => binding.event === 'keydown')) {
        if (binding.kind === 'confirm' ? keyboard?.confirm : keyboard?.activate)
          deliver(binding, event);
      }
      this.callbacks.key?.(event, record.key, node, record, keyboard);
    });
    if (added & listenerGroup.pointer) node.addEventListener('pointerdown', event => {
      if (node.dataset.retainFocus === 'true') event.preventDefault();
      if (record.fieldSession?.session === 'superseded_tail') this.fieldSession(record, 'input_started');
      this.callbacks.reading?.('pointer', event, record.key, node);
    });
    // SVG focus listeners make decorative glyphs implicit Tab stops in Chromium.
    // Caret/refocus observations only belong to native HTML fields.
    if ((added & listenerGroup.keyboardFocus) && node.namespaceURI !== svgNamespace) {
      node.addEventListener('focusin', event => this.callbacks.focus?.(event, record.key, node));
      node.addEventListener('focusout', event => this.callbacks.blur?.(event, record.key, node));
    }
    if (added & listenerGroup.reading) {
      node.addEventListener('wheel', event => this.callbacks.reading?.('scroll', event, record.key, node), { passive: true });
      node.addEventListener('touchmove', event => this.callbacks.reading?.('scroll', event, record.key, node), { passive: true });
      node.addEventListener('scroll', event => this.callbacks.reading?.('anchor', event, record.key, node), { passive: true });
    }
    if (!(added & listenerGroup.files)) return;
    // A pasted file targets the editor; its form's ReceiveFile control owns admission.
    const fileReceivers = () => {
      const candidates = node.form
        ? Array.from(this.records.values()).filter(candidate => candidate.node.form === node.form)
        : [record];
      return candidates.flatMap(candidate => candidate.events.some(binding => binding.kind === 'files') ? [candidate] : []);
    };
    for (const type of ['paste', 'drop']) node.addEventListener(type, event => {
      const receivers = fileReceivers();
      if (filesFromEvent(event).length && receivers.length) {
        event.preventDefault();
        for (const receiver of receivers.filter(receiver => !receiver.node.disabled && !receiver.node.matches('[aria-disabled="true"]')))
          for (const binding of receiver.events.filter(binding => binding.kind === 'files'))
            deliver(binding, event, receiver);
      }
    });
    node.addEventListener('dragover', event => {
      if (fileReceivers().length && Array.from(event.dataTransfer?.types ?? []).includes('Files')) event.preventDefault();
    });
  }
  refreshLinks(records = this.records.values()) {
    for (const record of records) {
      if (!record.markdown) continue;
      const counts = new Map();
      for (const link of record.node.querySelectorAll('a[href]')) {
        const href = link.getAttribute('href');
        const ordinal = counts.get(href) ?? 0;
        counts.set(href, ordinal + 1);
        const identity = stringifyJson(['native-link', record.key, href, ordinal]);
        link.dataset.key = identity;
        this.targets.set(identity, link);
      }
    }
  }
  input(record, action) {
    return action.op === 'element' ? { ...action, generation: record.generation } : action;
  }
  recordFor(key, tag, metadata) {
    let record = key === '' ? null : this.records.get(key);
    if (record && record.tag !== tag) {
      this.retireRecord(record); unmount(record.node); record = null;
    }
    if (!record) {
      const node = svgTags.has(tag)
        ? this.root.ownerDocument.createElementNS(svgNamespace, tag)
        : this.root.ownerDocument.createElement(tag);
      record = { key, tag, node, attributes: new Map(), styles: [], events: [], listenerGroups: 0, markdownTargets: new Map() };
      if (key !== '') {
        const owner = this;
        Object.defineProperty(record, 'generation', {
          get() { return owner.records.get(key) === this && node.isConnected ? owner.generation : null; },
        });
        this.records.set(key, record);
      }
    }
    record.metadata = metadata ?? {};
    if (key !== '') this.targets.set(key, record.node);
    return record;
  }
  retireRecord(record) {
    record.markdown?.dispose(); record.fences?.dispose();
    this.markdownRecords.delete(record);
    this.prefixFields.delete(record.node);
    this.prefixActions.delete(record);
    this.records.delete(record.key);
    this.targets.delete(record.key);
  }
  synchronizePrefixFields(inert) {
    for (const node of this.prefixFields) if (node.inert !== inert) node.inert = inert;
  }
  synchronizePrefixActions(pending) {
    for (const { node, attributes } of this.prefixActions) {
      // A pending source receipt disables activation without removing keyboard focus.
      const value = pending && !node.disabled ? 'true' : attributes.get('aria-disabled') ?? null;
      if (node.getAttribute('aria-disabled') === value) continue;
      if (value === null) node.removeAttribute('aria-disabled');
      else node.setAttribute('aria-disabled', value);
    }
  }
  restorePrefixField(key) {
    const record = this.records.get(key);
    if (!record) return;
    if (record.node.type === 'checkbox') record.node.checked = record.attributes.has('checked');
    else this.fieldSession(record, 'reject', record.attributes.get('value'));
  }
  elementChildren(record, children) {
    if (!this.isolated && record.key !== '') this.listeners(record);
    // Retained native editors keep their selection and composition session.
    reconcile(record.node, children);
    if (record.tag === 'select' && record.attributes.has('value') && 'value' in record.node && !this.composing.has(record.node)
        && record.node.value !== record.attributes.get('value')) record.node.value = record.attributes.get('value');
  }
  nativeOperations() {
    return {
      text: value => this.root.ownerDocument.createTextNode(value),
      element: (value, children) => {
        const record = this.recordFor(value.key, value.tag, value.metadata);
        record.events = value.events;
        this.properties(record, value.attributes, value.styles);
        const previous = record.node.childNodes;
        for (let index = 0; index < children.length; index++) {
          const child = children[index], mounted = previous[index];
          if (child.nodeType === 3 && mounted?.nodeType === 3) {
            if (mounted.data !== child.data) mounted.data = child.data;
            children[index] = mounted;
          }
        }
        this.elementChildren(record, children);
        return record.node;
      },
      markdown: value => {
        const record = this.recordFor(value.key, 'div', value.metadata);
        this.updateMarkdown(record, value);
        return record.node;
      },
    };
  }
  updateMarkdown(record, value) {
    this.markdownRecords.add(record);
    if (!this.isolated && record.key !== '') this.listeners(record);
    if (record.node.className !== 'markdown') record.node.className = 'markdown';
    record.metadata = value.metadata ?? {};
    const key = record.key;
    if (!record.markdown || !value.value.startsWith(record.text)) {
      record.markdown?.dispose(); record.markdownTargets.clear(); record.node.replaceChildren();
      const current = () => this.records.get(key) === record;
      record.markdown = new Markdown(record.node, { smooth: false, onChange: () => { if (current()) { this.refreshLinks([record]); this.callbacks.layout?.(); } },
        ...(record.metadata.origin === undefined ? {} : { interactiveFence: this.callbacks.interactiveFence }),
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
        if (this.records.get(key) !== record) return;
        const admitted = this.callbacks.fence?.(record.metadata, observed);
        if (admitted === false && (observed.closed || (observed.ending !== 'open' && observed.inputPrefix === record.text)))
          record.markdown.refusePreview(observed.ordinal);
      } });
      record.fences.sync({ text: value.value, epoch: stringifyJson(value.metadata.epoch),
        revision: value.metadata.revision, ending: value.metadata.ending ?? (value.complete ? 'complete' : 'open') });
    }
  }
  renderPicker(materialize, generation) {
    if (!this.document || this.hasPortals || this.document.measurement_pending) return false;
    const active = this.root.ownerDocument.activeElement;
    const focusedBefore = this.focusedKey(active);
    const previousScope = this.focusScope;
    const previousGeneration = this.generation;
    this.generation = generation;
    const output = materialize(this.nativeOperations());
    if (!output) { this.generation = previousGeneration; return false; }
    const { metadata, roots } = output;
    const picker = metadata.after === null ? null : roots.find(root => root.dataset.key === metadata.after);
    if (metadata.before !== null && metadata.before !== metadata.after) {
      const old = this.target(metadata.before);
      if (old) unmount(old);
    }
    if (picker && !picker.isConnected) this.target(metadata.layer_stack).append(picker);
    for (const [key, record] of this.records) {
      if (!record.node.isConnected) {
        this.retireRecord(record);
      }
    }
    this.focusScope = metadata.focus_scope;
    let targetUpdates = metadata.target_updates;
    if (metadata.partial_target_updates) {
      const retained = new Map(this.document.target_updates.map(update => [update.target, update]));
      for (const key of metadata.removed_target_updates) retained.delete(key);
      for (const update of targetUpdates) retained.set(update.target, update);
      targetUpdates = [...retained.values()];
    }
    this.document = { ...this.document, generation, focus_scope: this.focusScope, target_updates: targetUpdates };
    this.commitLayers(active, true);
    this.applyTargetUpdates(this.document);
    this.applyFocus(previousScope, focusedBefore);
    return true;
  }
  renderStream(materialize, generation) {
    if (!this.document || this.hasPortals || this.document.measurement_pending) return false;
    const previousGeneration = this.generation;
    this.generation = generation;
    const output = materialize(this.nativeOperations());
    // DEFENSE: A measured layout can remove a preview between stream receipts.
    // The ordinary document renderer will reconcile an unmounted preview.
    if (!output || output.roots.some(root => !root.isConnected)) {
      this.generation = previousGeneration;
      return false;
    }
    this.document = { ...this.document, generation };
    return true;
  }
  render(document, generation = 0) {
    this.refreshLinks();
    const active = this.root.ownerDocument.activeElement;
    const focusedBefore = this.focusedKey(active);
    this.document = document;
    const previousScope = this.focusScope;
    this.focusScope = document.focus_scope;
    this.generation = generation;
    this.targets.clear();
    const used = new Set();
    const portals = [];
    const create = (value, path, previous) => {
      if (value.kind === 'text') {
        if (previous?.nodeType !== 3) return this.root.ownerDocument.createTextNode(value.value);
        if (previous.data !== value.value) previous.data = value.value;
        return previous;
      }
      if (value.kind === 'portal') { portals.push({ value, path }); return null; }
      const key = value.key || path;
      used.add(key);
      const tag = value.kind === 'markdown' ? 'div' : value.tag;
      const record = this.recordFor(key, tag, value.metadata);
      if (value.kind === 'markdown') {
        this.updateMarkdown(record, value);
      } else {
        record.events = value.events;
        this.properties(record, value.attributes, value.styles);
        const previousChildren = value.children.some(child => child.kind === 'text') ? Array.from(record.node.childNodes) : [];
        const children = value.children.map((child, index) => create(child, `${key}/${index}`, previousChildren[index])).filter(Boolean);
        this.elementChildren(record, children);
      }
      return record.node;
    };
    const root = create(document.root, '@root');
    reconcile(this.root, [root]);
    this.hasPortals = portals.length !== 0;
    for (const { value, path } of portals) {
      const target = this.target(value.target);
      if (target) reconcile(target, value.children.map((child, index) => create(child, `${path}/${index}`)).filter(Boolean));
    }
    for (const [key, record] of this.records) {
      if (!used.has(key)) { this.retireRecord(record); unmount(record.node); }
    }
    this.refreshLinks();
    if (!this.isolated) this.commitLayers(active);
    this.applyTargetUpdates(document);
    for (const record of this.records.values()) if (record.metadata.code)
      this.callbacks.codePublication?.(record.metadata.code);
    this.applyFocus(previousScope, focusedBefore);
    if (document.title && this.root.ownerDocument.title !== document.title) this.root.ownerDocument.title = document.title;
  }
  commitLayers(active, keepUnderlay = false) {
    // DOM order is the declared layer order; retained-record insertion order can differ after resizing.
    const dialogs = Array.from(this.root.querySelectorAll('dialog[aria-modal="true"]'));
    this.refreshAnchors();
    const top = dialogs.at(-1) ?? null;
    const retain = keepUnderlay && top && dialogs.includes(this.modal);
    if (!retain && this.modal !== top && this.modal?.isConnected && this.modal.matches(':modal')) {
      const previous = this.modal;
      previous.close();
      if (dialogs.includes(previous)) previous.open = true;
    }
    this.modal = top;
    if (top && !top.matches(':modal')) {
      top.open = false;
      top.showModal();
    }
    this.confineAnchoredLayers();
    // Moving a retained header into its native drawer must not discard its focused control.
    if (active?.isConnected && active !== this.root.ownerDocument.activeElement &&
        (!top || top.contains(active)) && !active.closest('[inert]') && !active.disabled) {
      active.focus({ preventScroll: true });
    }
  }
  applyTargetUpdates(document) {
    const updatedTargets = new Set();
    for (const update of document.target_updates) {
      const target = this.target(update.target);
      if (!target) continue;
      updatedTargets.add(target);
      const retained = this.targetProperties ??= new WeakMap();
      const previous = retained.get(target) ?? { attributes: [], styles: [] };
      for (const name of previous.attributes) if (!update.attributes.some(value => value.name === name)) target.removeAttribute(name);
      for (const name of previous.styles) if (!update.styles.some(value => value.name === name)) target.style.removeProperty(name);
      for (const { name, value } of update.attributes) if (target.getAttribute(name) !== value) target.setAttribute(name, value);
      for (const { name, value } of update.styles) if (target.style.getPropertyValue(name) !== value) target.style.setProperty(name, value);
      retained.set(target, { attributes: update.attributes.map(value => value.name), styles: update.styles.map(value => value.name) });
    }
    for (const target of this.updatedTargets ?? []) if (!updatedTargets.has(target)) {
      const previous = this.targetProperties.get(target);
      for (const name of previous.attributes) target.removeAttribute(name);
      for (const name of previous.styles) target.style.removeProperty(name);
      this.targetProperties.delete(target);
    }
    this.updatedTargets = updatedTargets;
  }
  focusedKey(node = this.root.ownerDocument.activeElement) {
    return this.root.contains(node) ? node?.closest('[data-key]')?.dataset.key ?? null : null;
  }
  applyFocus(previousScope, focusedBefore) {
    if (!this.isolated) {
      const observeFocus = previous => {
        const focusedAfter = this.root.ownerDocument.activeElement;
        const focusedKey = this.focusedKey(focusedAfter);
        const eligible = this.root.contains(focusedAfter) &&
          (!this.modal || this.modal.contains(focusedAfter)) && focusAvailable(focusedAfter);
        const scope = this.focusScope.at(-1);
        // Only a retained child of a temporary scope can need physical
        // recovery. Skip the root layout query if that child is still visible.
        const temporary = scope?.type === 'temporary' && focusedKey !== null;
        const focusedVisible = temporary && focusVisible(focusedAfter);
        const scopeRoot = temporary && !focusedVisible ? this.resolveTarget(scope.identity) : null;
        const rootEligible = focusAvailable(scopeRoot) && scopeRoot.matches('dialog[tabindex],button,input,select,textarea,a[href],[tabindex]');
        return this.callbacks.focusPlan?.({ previous, current: this.focusScope, eligible,
          focused_before: focusedBefore, focused_after: focusedKey,
          focused_visible: focusedVisible, root_visible: rootEligible && focusVisible(scopeRoot), root_eligible: rootEligible });
      };
      const focusTarget = focus => {
        const target = this.resolveTarget(focus.target, { fallback: focus.fallback });
        const container = this.modalRecord()?.node;
        const recoveringContainer = target === container && focus.target === container?.dataset.key;
        const canFocusContainer = target?.matches('dialog') && target.hasAttribute('tabindex') && focusAvailable(target);
        if (!target || (recoveringContainer && !canFocusContainer)) { this.pendingFocus = focus; return; }
        this.pendingFocus = null;
        this.applyingFocus = true;
        try { revealAndFocus(target); } finally { this.applyingFocus = false; }
      };
      const focus = observeFocus(previousScope) ?? this.pendingFocus;
      if (focus) {
        focusTarget(focus);
        // A requested focus can expose a different clipped child. Observe the
        // completed native focus before applying the scope's physical recovery.
        if (this.focusScope.at(-1)?.type === 'temporary') {
          const recovery = observeFocus(this.focusScope);
          if (recovery) focusTarget(recovery);
        }
      }
    }
  }
  restoreField(key, value) {
    const target = this.resolveTarget(key, { modal: false });
    const record = target && this.records.get(target.dataset.key);
    // DEFENSE: The owning surface may have removed a field before its rejection reaches the native publication.
    if (!record) return;
    // Ordinary assignments restore the published value; interactive fields may
    // supply their newer canonical value explicitly.
    this.fieldSession(record, 'reject', value ?? record.attributes.get('value'));
  }
  async whenSettled() {
    const results = await Promise.all(Array.from(this.markdownRecords, record => record.markdown.whenSettled()));
    return !this.disposed && results.every(Boolean);
  }
  isCaughtUp() {
    if (this.disposed) return false;
    for (const record of this.markdownRecords)
      if (!record.markdown.isCaughtUp() || (record.fences && !record.fences.isCaughtUp())) return false;
    return true;
  }
  async whenCaughtUp() {
    const pending = [];
    for (const record of this.markdownRecords) {
      if (record.markdown) pending.push(record.markdown.whenCaughtUp());
      if (record.fences) pending.push(record.fences.whenCaughtUp());
    }
    if (!pending.length) return !this.disposed;
    const results = await Promise.all(pending);
    return !this.disposed && results.every(Boolean);
  }
  reset() {
    for (const record of this.records.values()) { record.markdown?.dispose(); record.fences?.dispose(); }
    reconcile(this.root, []); this.records.clear(); this.targets.clear(); this.modal = null;
    this.markdownRecords.clear(); this.prefixFields.clear(); this.prefixActions.clear();
    this.document = null; this.focusScope = []; this.pendingFocus = null; this.updatedTargets = new Set(); this.targetProperties = new WeakMap();
  }
  dispose() {
    if (!this.isolated) this.root.ownerDocument.defaultView.removeEventListener('resize', this.resizeMenus);
    this.root.removeEventListener('focusin', this.anchorFocus);
    this.root.removeEventListener('focusout', this.anchorFocus);
    this.disposed = true;
    this.reset();
  }
}
