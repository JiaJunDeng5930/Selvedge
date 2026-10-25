import { boundary } from './model-boundary.mjs';
import { browser, interaction } from './browser-model-boundary.mjs';
import { JsonNumber, parseJson, stringifyJson } from './json-tokens.mjs';
import { Renderer, filesFromEvent } from './renderer.mjs';
import { editorKeyboard, applyByteSelection } from './keyboard.mjs';
import { observeConnection } from './connection.mjs';
import { AudioRuntime } from './audio.mjs';
import { InteractiveSnapshotStorage } from './interactive-storage.mjs';
import { createLayoutRevealer, revealAndFocus } from './layout-reveal.mjs';
import { PresentationMotion } from './presentation-motion.mjs';
import { safeHref } from './markdown.mjs';
import { createPhysicalMeasurer } from './physical-measurement.mjs';

const surface = document.getElementById('surface');
const announcements = document.getElementById('announcements');
const files = new Map();
const transfers = new Map();
const assessments = new Map();
const resources = new Set();
const timers = new Set();
const readings = new Map();
const readingMeasurements = new Map();
const readingPointers = new Map();
const readingLayouts = new WeakMap();
const restoredReadingOffsets = new WeakMap();
const codeBlocks = new Map();
const storagePolicy = interaction('interactive_storage_policy');
const storage = new InteractiveSnapshotStorage({ ...storagePolicy,
  maximumDocuments: Number(storagePolicy.maximumDocuments instanceof JsonNumber ? storagePolicy.maximumDocuments.source : storagePolicy.maximumDocuments),
  maximumBytes: Number(storagePolicy.maximumBytes instanceof JsonNumber ? storagePolicy.maximumBytes.source : storagePolicy.maximumBytes) });
const reveal = createLayoutRevealer(surface);
const motion = new PresentationMotion(surface);
let state = interaction('initial');
let world = null;
let publication = { generation: 0, phase: 'awaiting', namespace: '', sequence: 0, displayed_generation: null };
let environment = null;
let measuring = null;
let measureAgain = false;
let renderAfterMeasurement = false;
let connection = null;
let disposed = false;
let clockRefresh = null;
let sourceFresh = false;
let layoutFrame = null;
let pendingHistoryLocation = null;
let focusRequest = 0;
let pendingFocus = null;
let suspendedFocus = null;
const ticketKey = value => stringifyJson(value);
const integral = value => BigInt(value instanceof JsonNumber ? value.source : value);

function taskObservation(effect, fields) {
  return effect.task_id === undefined ? fields : { ...fields, task_id: effect.task_id };
}

const requestScope = () => ({ namespace: publication.namespace, sequence: publication.sequence, ticket: state.services.connection.ticket });
const ownsRequestFailure = scope => publicationEvent('request_failure', { expected_namespace: scope.namespace,
  expected_sequence: scope.sequence, ticket: scope.ticket, connection: state.services.connection });
const authorizationRevoked = error => error.status === 401 || error.status === 403;
function observeRequestFailure(error, scope) {
  if (authorizationRevoked(error) && ownsRequestFailure(scope))
    dispatch({ type: 'disconnected', ticket: scope.ticket, error: error.message, revoked: true });
}
async function request(url, options = {}, binary = false) {
  const scope = requestScope();
  let response;
  try {
    response = await fetch(url, { ...options, credentials: 'same-origin' });
    if (binary) {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return await response.blob();
    }
    const text = await response.text();
    const value = text ? parseJson(text) : null;
    // DEFENSE: Authentication failures and rejected external requests are observable service outcomes.
    if (!response.ok) {
      const error = new Error(typeof value?.error === 'string' ? value.error : value?.error?.message ?? `HTTP ${response.status}`);
      error.body = value;
      throw error;
    }
    return value;
  } catch (error) {
    // DEFENSE: A denial can be truncated or contain invalid JSON; its HTTP status
    // still revokes the source that owned this request, never a later source.
    if (response) error.status ??= response.status;
    error.requestScope = scope;
    observeRequestFailure(error, scope);
    throw error;
  }
}
const post = (url, value, signal) => request(url, { method: 'POST', signal,
  headers: { 'content-type': 'application/json' }, body: stringifyJson(value) });

async function requestCommand(command, signal) {
  const expected = publication.namespace;
  let body;
  try { body = await post('/api/browser/command', { command }, signal); }
  catch (error) {
    // DEFENSE: A rejected committed command still returns its authoritative world and reply with a non-2xx status.
    if (error.body && Object.hasOwn(error.body, 'program') && Object.hasOwn(error.body, 'reply')) body = error.body;
    else throw error;
  }
  if (!publicationEvent('completion', { expected_namespace: expected, incoming_namespace: body.namespace })) return;
  snapshot(body, expected);
  return body.reply;
}

function publicationEvent(event, values = {}) {
  return browser('publication', { ...publication, event, ...values });
}
function admitted(generation) {
  return publicationEvent('admit', { receipt_generation: generation });
}
function snapshot(body, expected = publication.namespace, authenticating = false, authenticationTicket) {
  const receipt = browser('snapshot', { ...publication, expected_namespace: expected, incoming_namespace: body.namespace,
    incoming_sequence: body.sequence, authenticating,
    sources_fresh: sourceFresh,
    ...(authenticating ? { authentication_ticket: authenticationTicket, connection: state.services.connection } : {}) });
  sourceFresh = receipt.sources_fresh;
  if (!receipt.accepted) return receipt.authenticated;
  if (!receipt.install_world) return true;
  if (receipt.install_world) {
    if (body.namespace !== publication.namespace) retireDocumentViews();
    world = body.program;
  }
  publication = { ...publication, namespace: body.namespace, sequence: body.sequence };
  dispatch({ type: 'snapshot', world });
  return true;
}
function retireDocumentViews() {
  for (const entry of codeBlocks.values()) for (const physical of entry.views.values()) physical.renderer?.dispose();
  codeBlocks.clear(); readings.clear(); files.clear(); renderer.reset();
  for (const node of readingMeasurements.keys()) retireReadingMeasurement(node);
  pendingHistoryLocation = null; pendingFocus = null; suspendedFocus = null; focusRequest++;
  for (const controller of assessments.values()) controller.abort();
  assessments.clear();
  for (const resource of resources) URL.revokeObjectURL(resource);
  resources.clear();
}
function fatal(error) {
  publication = publicationEvent('failure', { reason: error.message });
  render();
}
function synchronizeNativeAuthority() {
  const inert = !publicationEvent('ready');
  if (inert && !surface.inert) {
    const node = document.activeElement;
    suspendedFocus = surface.contains(node) ? { node, attempt: focusRequest } : null;
  }
  surface.inert = inert;
  // Native modal dialogs escape ancestor inertness; apply the same receipt to
  // those real DOM roots as well as to the ordinary document tree.
  for (const dialog of surface.querySelectorAll('dialog')) dialog.inert = inert;
  if (!inert && suspendedFocus) {
    const retained = suspendedFocus; suspendedFocus = null;
    // Toggling native inertness can blur an unchanged editor. Preserve that
    // physical focus unless another focus request or replacement superseded it.
    if (retained.attempt === focusRequest && retained.node.isConnected &&
        !retained.node.matches(':disabled,[aria-disabled="true"]') &&
        document.activeElement === document.body) retained.node.focus({ preventScroll: true });
  }
}
function renderRecovery(reason) {
  surface.inert = false;
  renderer.render(browser('recovery', { root_font_size_milli: physical.viewport().root_font_size_milli,
    generation: publication.generation, reason }), publication.generation);
}
function dispatch(input) {
  if (disposed) return;
  const decision = interaction('step', { state, input, world, environment, generation: publication.generation, namespace: publication.namespace, now: BigInt(Math.floor(Date.now() / 1000)), displayed_generation: publication.displayed_generation, semantic_lagged: publicationEvent('semantic_pending') });
  state = decision.state;
  const retainedFiles = new Set(decision.file_handles);
  for (const handle of files.keys()) if (!retainedFiles.has(handle)) files.delete(handle);
  if (decision.feedback_update !== 'keep') {
    const error = decision.error;
    const message = typeof error === 'string' ? error : error && typeof error === 'object'
      ? (typeof error.code === 'string' && typeof error.message === 'string' ? `${error.code}: ${error.message}`
        : typeof error.message === 'string' ? error.message : JSON.stringify(error))
      : '';
    announcements.textContent = message;
    const visible = decision.visible_error === true && message !== '';
    announcements.classList.toggle('visually-hidden', !visible);
    announcements.setAttribute('role', visible ? 'alert' : 'status');
    announcements.setAttribute('aria-live', visible ? 'assertive' : 'polite');
  }
  publication = publicationEvent(decision.publication_event);
  if (decision.publication_event !== 'keep') render();
  for (const effect of decision.effects) execute(effect).catch(fatal);
  return decision.handled;
}
function retryFocus() {
  const pending = pendingFocus;
  if (!pending) return;
  // DEFENSE: a native focus request can outlive another focus or its journal.
  if (pending.attempt !== focusRequest || pending.namespace !== publication.namespace) { pendingFocus = null; return; }
  if (document.visibilityState !== 'visible' || publicationEvent('pending') || !admitted(renderer.generation)) return;
  const target = renderer.resolveTarget(pending.effect.key, { fallback: pending.effect.fallback, recoverMissing: true });
  if (!target) return;
  pendingFocus = null;
  revealAndFocus(target);
}
function refreshClock() {
  // DEFENSE: Background tabs can still run throttled intervals, and their hidden UI should refresh when visible again.
  if (document.visibilityState !== 'visible') return;
  dispatch({ type: 'clock_observed', now: BigInt(Math.floor(Date.now() / 1000)) });
}
function render() {
  if (disposed) return;
  const recovery = publicationEvent('recovery');
  if (recovery !== null) { renderRecovery(recovery); return; }
  if (!environment) return;
  surface.dataset.displayPending = String(publicationEvent('pending'));
  if (measuring && renderer.document) {
    renderAfterMeasurement = true; measureAgain = true; return;
  }
  const plan = interaction('observe', { state, world, environment, generation: publication.generation,
    namespace: publication.namespace, now: BigInt(Math.floor(Date.now() / 1000)), displayed_generation: publication.displayed_generation, semantic_lagged: publicationEvent('semantic_pending') });
  surface.dataset.displayPending = String(publicationEvent('pending'));
  if (plan.measurement_pending && renderer.document && !renderer.document.measurement_pending) {
    refreshPhysical().catch(fatal); return;
  }
  renderer.render(plan, publication.generation);
  surface.dataset.sourcesFresh = String(sourceFresh);
  physical.refresh();
  if (!plan.measurement_pending) {
    publication = publicationEvent('document', { receipt_generation: publication.generation });
    synchronizeNativeAuthority();
    const generation = publication.generation;
    renderer.whenCaughtUp().then(caughtUp => {
      if (!caughtUp || disposed) return;
      publication = publicationEvent('publish', { receipt_generation: generation });
      // The receipt changes input authority, not the compiled state/world/environment.
      // Keep the same DOM and finish the native work that was waiting for publication.
      surface.dataset.displayPending = String(publicationEvent('pending'));
      synchronizeNativeAuthority();
      if (publicationEvent('ready')) renderer.refreshNativeTargets();
      retryHistoryLocation(); retryFocus();
    }).catch(fatal);
  }
  reveal(); motion.refresh(); layoutReading(); retryHistoryLocation();
  refreshPhysical().catch(fatal);
}
async function refreshPhysical() {
  if (measuring) { measureAgain = true; return measuring; }
  measuring = (async () => {
    do {
      measureAgain = false;
      const requestedRootFontSize = physical.viewport().root_font_size_milli;
      const specs = browser('font_specs', { root_font_size_milli: requestedRootFontSize });
      const observedGeneration = publication.generation;
      let observations;
      try { observations = await physical.measure(specs); }
      catch (error) {
        // DEFENSE: a font/DOM observation can reject after another generation has
        // replaced its document. Its failure cannot replace that newer page.
        const failure = browser('measurement_failure', { measured_generation: observedGeneration,
          current_generation: publication.generation, reason: error.message });
        if (failure === null) { measureAgain = true; continue; }
        // Apply the admitted failure before another promise can publish a newer generation.
        fatal(error);
        return;
      }
      const receipt = browser('environment', { observations, requested_root_font_size_milli: requestedRootFontSize,
        measured_generation: observedGeneration, current_generation: publication.generation,
        system_dark: matchMedia('(prefers-color-scheme: dark)').matches,
        reduced_motion: matchMedia('(prefers-reduced-motion: reduce)').matches });
      if (receipt.stale) { measureAgain = true; continue; }
      const next = receipt.environment;
      const changed = stringifyJson(next) !== stringifyJson(environment);
      environment = next;
      for (const update of browser('responsive_rows', { rows: observations.responsive_rows })) {
        const row = renderer.target(update.key);
        row.style.setProperty('flex-direction', update.direction);
        row.dataset.nativeRowDirection = update.direction;
        if (update.supporting_form !== undefined) row.setAttribute('data-supporting-form', update.supporting_form);
      }
      if (changed) dispatch({ type: 'environment_observed' });
    } while (measureAgain && !disposed);
  })();
  try { await measuring; } finally {
    measuring = null;
    if (renderAfterMeasurement && !disposed) { renderAfterMeasurement = false; render(); }
  }
}
function observedSelection(node, composing = false) {
  const encode = value => new TextEncoder().encode(value).length;
  return { start: encode(node.value.slice(0, node.selectionStart ?? node.value.length)),
    end: encode(node.value.slice(0, node.selectionEnd ?? node.value.length)), direction: node.selectionDirection, composing };
}
function registerFiles(action, selected) {
  for (const file of selected) {
    const handle = crypto.randomUUID(); files.set(handle, file);
    dispatch({ ...action, value: { handle, name: file.name, mime: file.type, bytes: file.size } });
  }
}
const renderer = new Renderer(surface, {
  resolveTarget(source) { return browser('resolve_target', source); },
  fieldSession(source) { return browser('field_session', source); },
  focusPlan(source) { return browser('focus_plan', source); },
  keyboard(source) { return browser('key', source); },
  focus(event, key, node) {
    focusRequest++;
    if (event.target !== node || typeof node.selectionStart !== 'number') return;
    const record = renderer.records.get(key);
    const binding = record?.events.find(binding => binding.kind === 'value' && binding.action.op === 'element');
    if (!binding || !record.metadata.selection_enabled || !admitted(record.generation)) return;
    dispatch({ ...binding.action, gesture: 'selection',
      value: { ...observedSelection(node, renderer.composing.has(node)), refocus: true } });
  },
  composition(event, key, node) {
    const record = renderer.records.get(key);
    const binding = record?.events.find(binding => binding.kind === 'value' && binding.action.op === 'element');
    if (binding && record.metadata.selection_enabled && admitted(record.generation))
      dispatch({ ...binding.action, gesture: 'selection', value: observedSelection(node, true) });
  },
  blur(event, key, node) {
    if (event.target !== node || typeof node.selectionStart !== 'number') return;
    const record = renderer.records.get(key);
    const binding = record?.events.find(binding => binding.kind === 'value' && binding.action.op === 'element');
    if (!binding || !record.metadata.selection_enabled || !admitted(record.generation)) return;
    dispatch({ ...binding.action, gesture: 'selection',
      value: { ...observedSelection(node, renderer.composing.has(node)), blur: true } });
  },
  event(binding, event, key, node, generation) {
    if (binding.kind === 'retry_render') {
      event.preventDefault(); publication = publicationEvent('retry');
      refreshPhysical().then(render).catch(fatal); return;
    }
    if (!admitted(generation)) return;
    if (binding.kind === 'files') {
      registerFiles(binding.action, filesFromEvent(event, node));
      if (node.type === 'file') node.value = '';
    }
    else if (binding.kind === 'value') dispatch({ ...binding.action, value: node.value,
      raw: node.value, selection: observedSelection(node, event.isComposing || renderer.composing.has(node)) });
    else if (binding.kind === 'values') dispatch({ ...binding.action, value: Array.from(node.selectedOptions, option => option.value) });
    else if (binding.kind === 'checked') dispatch({ ...binding.action, value: node.checked });
    else {
      event.preventDefault();
      dispatch(binding.kind === 'dismiss' ? { ...binding.action, value: 'escape' } : binding.action);
    }
  },
  key(event, key, node, record, keyboard) {
    // DEFENSE: A handled keydown still bubbles through ancestor renderer records.
    if (event.defaultPrevented) return;
    if (!admitted(record.generation)) return;
    const composing = event.isComposing || renderer.composing.has(node);
    if (record.metadata.key_input && keyboard.unmodified) {
      const input = { op: 'element', key, gesture: 'key', generation: record.generation, value: { key: event.key } };
      if (interaction('accepts_element', { state, input, world, environment, generation: publication.generation,
          namespace: publication.namespace, displayed_generation: publication.displayed_generation, now: BigInt(Math.floor(Date.now() / 1000)) })) {
        event.preventDefault(); dispatch(input); return;
      }
    }
    const form = node.form;
    if (form && (node.tagName === 'TEXTAREA' || node.tagName === 'INPUT')) {
      const submitter = form.querySelector('button[type="submit"],input[type="submit"]');
      editorKeyboard(event, observation => browser('editor_key', { ...observation,
        scope: renderer.focusScope, within_scope: !!renderer.modal?.contains(form), composer_binding: record.metadata.composer_binding === true, multiline: node.tagName === 'TEXTAREA', enabled: !node.disabled && !submitter?.disabled && submitter?.getAttribute('aria-disabled') !== 'true', pending: submitter?.getAttribute('aria-busy') === 'true' }), () => form.requestSubmit(), composing);
    }
    const dialog = node.closest('dialog[open],[aria-modal="true"]');
    if (dialog && event.key === 'Tab') {
      const targets = Array.from(dialog.querySelectorAll('button,a[href],input,textarea,select,[tabindex]')).filter(target =>
        target.tabIndex >= 0 && !target.matches(':disabled,[aria-disabled="true"]') && !target.closest('[inert],[hidden]') &&
        target.getClientRects().length && getComputedStyle(target).visibility !== 'hidden');
      const keys = targets.map((_, index) => String(index));
      const next = browser('focus_cycle', { current: String(targets.indexOf(event.target)), targets: keys, backward: event.shiftKey });
      if (next !== null) { event.preventDefault(); targets[Number(next)].focus(); }
    }
    if (node.dataset.readingRoot === 'true' && event.target.closest('[data-reading-root="true"]') === node) {
      const state = readingState(key, node);
      acceptReading(key, node, browser('reading', { state, event: 'key', keyboard: event.key,
        editable: event.target.matches('input,textarea,select') }));
    }
  },
  reading(type, event, key, node) {
    if (node.dataset.readingRoot !== 'true') return;
    if (type === 'scroll' ? event.target.closest('[data-reading-root="true"]') !== node : event.target !== node) return;
    if (type === 'pointer') {
      const rect = node.getBoundingClientRect(), style = getComputedStyle(node);
      const left = rect.left + node.clientLeft;
      const right = left + node.clientWidth;
      const inLeftGutter = event.clientX < left && node.clientLeft > Number.parseFloat(style.borderLeftWidth);
      const inRightGutter = event.clientX >= right && rect.right - right > Number.parseFloat(style.borderRightWidth);
      if (!inLeftGutter && !inRightGutter) return;
    }
    const state = readingState(key, node);
    if (type === 'scroll' || type === 'pointer') {
      requestReadingAnchor(key, node, type === 'pointer' ? event.pointerId : undefined);
      acceptReading(key, node, browser('reading', { state, event: 'scroll' }));
    } else if (state.intent === 'history') {
      // DEFENSE: restoring a bookmark emits scroll even when the browser clamps
      // it before asynchronous Markdown mounts. That receipt is not a new user position.
      if (restoredReadingOffsets.get(node) === node.scrollTop) return;
      requestReadingAnchor(key, node);
    }
  },
  menuGeometry(bounds) {
    return browser('menu_viewport_correction', Object.fromEntries(
      ['left', 'top', 'width', 'height'].map(name => [name, new JsonNumber(String(bounds[name]))])));
  },
  layout() {
    if (layoutFrame === null) layoutFrame = requestAnimationFrame(() => {
      layoutFrame = null; reveal(); renderer.confineMenus(); layoutReading();
    });
  },
  codeSource(source, ordinal, text, view) {
    publishCode(browser('code_identity', { source, ordinal }), view, text);
  },
  codePublication({ identity, view, text }) { publishCode(identity, view, text); },
  codeIdentity(source, ordinal) { return browser('code_identity', { source, ordinal }); },
  codeTargets(identity, view) { return browser('code_targets', { identity, view }); },
  fence(metadata, observed) {
    dispatch({ type: 'code_observed', origin: metadata.origin, document_key: metadata.document_key,
      epoch: metadata.epoch, revision: observed.inputRevision, ordinal: observed.ordinal,
      fence_kind: observed.kind, info_complete: observed.infoComplete,
      raw_info: observed.info, code_prefix: observed.code, closed: observed.closed,
      input_prefix: observed.inputPrefix });
  },
});

const physical = createPhysicalMeasurer({ surface, onChange: () => refreshPhysical().catch(fatal) });

function publishCode(identity, view, text) {
  const key = browser('code_key', { identity });
  let entry = codeBlocks.get(key);
  if (!entry) {
    const decision = browser('code_initial', { identity, view, text, environment });
    entry = { key, identity, state: decision.state, views: new Map() };
    codeBlocks.set(key, entry);
  }
  entry.views.set(stringifyJson(view), entry.views.get(stringifyJson(view)) ?? { view, renderer: null });
  codeStep(entry, { type: 'source', text });
}
function renderCode(entry, decision) {
  entry.state = decision.state;
  for (const physical of entry.views.values()) {
    const plan = browser('code_present', { state: entry.state, view: physical.view, environment });
    const target = renderer.target(plan.targets.toolbar);
    if (target) {
      if (!physical.renderer || physical.renderer.root !== target) {
        physical.renderer?.dispose();
        physical.renderer = new Renderer(target, { event(binding, event) {
          event.preventDefault(); codeStep(entry, binding.action.input);
        } });
      }
      physical.renderer.render(plan.document);
    }
    const code = renderer.target(plan.targets.body);
    if (code) for (const { name, value } of plan.body_styles) code.style.setProperty(name, value);
  }
  for (const effect of decision.effects) {
    if (effect.type === 'clipboard') navigator.clipboard.writeText(effect.text).then(
      () => { if (codeBlocks.get(entry.key) === entry) codeStep(entry, { type: 'copied', ticket: effect.ticket, ok: true }); },
      () => { if (codeBlocks.get(entry.key) === entry) codeStep(entry, { type: 'copied', ticket: effect.ticket, ok: false }); });
    else if (effect.type === 'expiry') {
      const timer = setTimeout(() => {
        timers.delete(timer);
        if (codeBlocks.get(entry.key) === entry) codeStep(entry, { type: 'expire', ticket: effect.ticket });
      }, Number(effect.delay_ms)); timers.add(timer);
    }
  }
}
function codeStep(entry, input) {
  // DEFENSE: a queued native event or clipboard completion can outlive its namespace's code view.
  if (codeBlocks.get(entry.key) !== entry) return;
  renderCode(entry, browser('code_step', { state: entry.state, input, environment, view: entry.views.values().next().value.view }));
}

const readingKey = node => node.dataset.taskId;
function readingState(key, node) {
  const bound = browser('reading_bind', { generation: new JsonNumber(node.dataset.readerGeneration),
    state: readings.get(readingKey(node)) ?? null });
  readings.set(readingKey(node), bound);
  return bound;
}
function acceptReading(key, node, decision, locationTarget) {
  const previous = readings.get(readingKey(node))?.intent ?? 'follow';
  readings.set(readingKey(node), decision.state);
  for (const effect of decision.effects) {
    if (effect.type === 'leave_viewport') {
      restoredReadingOffsets.delete(node);
      node.scrollTo({ top: node.scrollTop, left: node.scrollLeft, behavior: 'instant' });
    }
    else if (effect.type === 'align_latest') node.scrollTo({ top: node.scrollHeight, behavior: effect.animate ? 'smooth' : 'instant' });
    else if (effect.type === 'reserve_composer') node.style.setProperty('scroll-padding-block-end', effect.clearance);
    else if (effect.type === 'cancel_anchor') retireReadingMeasurement(node);
    else if (effect.type === 'locate_message' && locationTarget) {
      node.scrollTo({ top: node.scrollTop + locationTarget.getBoundingClientRect().top - node.getBoundingClientRect().top,
        left: node.scrollLeft, behavior: 'instant' });
      observeReadingAnchor(key, node, decision.state);
    }
    else if (effect.type === 'preserve_anchor' && !currentReadingMeasurement(node)) {
      const target = Array.from(node.querySelectorAll('[data-reading-identity]')).find(
        candidate => candidate.dataset.readingIdentity === effect.anchor.key);
      if (target) {
        node.scrollTop += target.getBoundingClientRect().top - node.getBoundingClientRect().top - Number(effect.anchor.offset);
        restoredReadingOffsets.set(node, node.scrollTop);
      }
    } else if (effect.type === 'measure_anchor') {
      if (currentReadingMeasurement(node)) requestReadingAnchor(key, node);
      else observeReadingAnchor(key, node, decision.state);
    }
  }
  if (previous !== decision.state.intent && node.dataset.readerGeneration !== undefined)
    dispatch({ type: 'read_timeline', task: new JsonNumber(node.dataset.taskId),
      generation: new JsonNumber(node.dataset.readerGeneration), intent: decision.state.intent });
}
function observeReadingAnchor(key, node, state) {
  const viewport = node.getBoundingClientRect();
  const anchor = Array.from(node.querySelectorAll('[data-reading-anchor]')).find(target => {
    const bounds = target.getBoundingClientRect();
    return bounds.bottom > viewport.top && bounds.top < viewport.bottom;
  });
  if (anchor) readings.set(readingKey(node), browser('reading', { state, event: 'anchor', anchor: {
    key: anchor.dataset.readingIdentity, offset: String(anchor.getBoundingClientRect().top - viewport.top) } }).state);
}
function retireReadingMeasurement(node) {
  const pending = readingMeasurements.get(node);
  if (pending?.frame !== null && pending?.frame !== undefined) cancelAnimationFrame(pending.frame);
  for (const pointer of pending?.pointers ?? []) readingPointers.delete(pointer);
  readingMeasurements.delete(node);
}
function currentReadingMeasurement(node) {
  const pending = readingMeasurements.get(node);
  if (pending && (!node.isConnected || pending.generation !== node.dataset.readerGeneration || pending.key !== node.dataset.key)) {
    retireReadingMeasurement(node); return null;
  }
  return pending;
}
// These are pending native anchor observations, not a second reading policy.
// Browser.Reading owns the intent and bookmark; a drag's measurement settles
// after native scrolling, and layout correction cannot race that observation.
function requestReadingAnchor(key, node, pointer) {
  let pending = currentReadingMeasurement(node);
  if (!pending) {
    pending = { key, generation: node.dataset.readerGeneration, frame: null, pointers: new Set() };
    readingMeasurements.set(node, pending);
  }
  if (pointer !== undefined) { pending.pointers.add(pointer); readingPointers.set(pointer, node); }
  if (pending.frame !== null) return;
  pending.frame = requestAnimationFrame(() => {
    pending.frame = null;
    // DEFENSE: an anchor frame can outlive the task reader that requested it.
    if (currentReadingMeasurement(node) !== pending) return;
    const state = readingState(key, node);
    if (state.intent === 'history') observeReadingAnchor(key, node, state);
    if (!pending.pointers.size) retireReadingMeasurement(node);
  });
}
function endReadingPointer(event) {
  const node = readingPointers.get(event.pointerId);
  if (!node) return;
  readingPointers.delete(event.pointerId);
  const pending = currentReadingMeasurement(node);
  if (pending) { pending.pointers.delete(event.pointerId); requestReadingAnchor(pending.key, node); }
}
window.addEventListener('pointerup', endReadingPointer, true);
window.addEventListener('pointercancel', endReadingPointer, true);
function retryHistoryLocation() {
  const pending = pendingHistoryLocation;
  if (!pending) return;
  // DEFENSE: a selected history message can await physical publication while
  // navigation replaces its journal or reader occurrence.
  if (pending.namespace !== publication.namespace) { pendingHistoryLocation = null; return; }
  const root = [...renderer.records.values()].map(record => record.node).find(node =>
    node.dataset.readingRoot === 'true' && node.dataset.taskId === integral(pending.task_id).toString());
  if (root && root.dataset.readerGeneration !== integral(pending.reader_generation).toString()) {
    pendingHistoryLocation = null; return;
  }
  if (!root || !publicationEvent('ready')) return;
  const target = renderer.resolveTarget(pending.key, { modal: false });
  if (!target || !root.contains(target)) return;
  pendingHistoryLocation = null;
  retireReadingMeasurement(root);
  const key = root.dataset.key;
  acceptReading(key, root, browser('reading', { state: readingState(key, root), event: 'locate',
    index: pending.message_index }), target);
}
function readingStep(key, node, event) {
  const state = readingState(key, node);
  const dock = node.closest('[data-view]')?.querySelector('[data-composer-dock]');
  const decision = browser('reading', { state, event,
    dock_height: String(dock?.getBoundingClientRect().height ?? 0),
    viewport_height: String(node.clientHeight), reduced_motion: matchMedia('(prefers-reduced-motion: reduce)').matches });
  acceptReading(key, node, decision);
}
function layoutReading() {
  for (const [key, record] of renderer.records) {
    const node = record.node;
    if (node.dataset.readingRoot !== 'true') continue;
    const dock = node.closest('[data-view]')?.querySelector('[data-composer-dock]');
    const signature = JSON.stringify([node.dataset.readerGeneration, node.clientWidth, node.clientHeight,
      node.scrollHeight, dock?.getBoundingClientRect().height ?? 0]);
    if (readingLayouts.get(node) === signature && node.style.getPropertyValue('scroll-padding-block-end') !== '') continue;
    readingLayouts.set(node, signature);
    readingStep(key, node, 'layout');
  }
}
function dismiss(event) {
  // DEFENSE: An inner menu can consume Escape before it reaches the enclosing dialog.
  if (event.defaultPrevented) return;
  const modal = renderer.modalRecord();
  const dismissal = modal?.events.find(binding => binding.kind === 'dismiss');
  const behavior = modal?.metadata.layer;
  if (!dismissal || !admitted(modal.generation)) return;
  if (event.type === 'keydown' && event.key === 'Escape' && behavior.escape || event.type === 'pointerdown' && behavior.outside && (!modal.node.contains(event.target) || event.target === modal.node && (() => {
    const box = modal.node.getBoundingClientRect();
    return event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom;
  })())) {
    event.preventDefault(); dispatch({ ...dismissal.action, value: event.type === 'keydown' ? 'escape' : 'outside' });
  }
}
document.addEventListener('keydown', dismiss);
document.addEventListener('pointerdown', dismiss);

const audioEventNames = {
  Capabilities: 'audio_capabilities', CapabilitiesFailed: 'audio_capabilities_failed',
  Refresh: 'audio_refresh', Captured: 'audio_captured', Transcribed: 'audio_transcribed',
  TaskCreated: 'voice_task_created', VoiceReady: 'voice_ready', LiveText: 'voice_text',
  Failed: 'audio_failed', Ended: 'audio_ended', Released: 'audio_released',
};
const audio = new AudioRuntime({
  emit(name, values) {
    const input = { ...values, type: audioEventNames[name] };
    if (Object.hasOwn(values, 'reason')) { input.error = values.reason; delete input.reason; }
    if (Object.hasOwn(values, 'task')) { input.task_id = values.task; delete input.task; }
    dispatch(input);
  },
  request,
  async createTask(command, signal) {
    const reply = await requestCommand(command, signal);
    if (reply === undefined) throw new Error('The task reply belongs to another browser source.');
    // DEFENSE: Task creation can be rejected while returning an owned world snapshot.
    if (!reply.ok) throw new Error(reply.error?.message ?? 'Voice task creation failed');
    return integral(reply.result.task_id);
  },
  field(editor) {
    return Array.from(renderer.records.values()).find(record => record.metadata.editor && ticketKey(record.metadata.editor) === ticketKey(editor))?.node;
  },
  browserId: crypto.randomUUID(), limits: boundary('audio.contract', {}),
  loginTarget(url) {
    const parsed = new URL(url);
    return boundary('audio.login_target', { url: parsed.href, protocol: parsed.protocol,
      hostname: parsed.hostname, port: parsed.port, pathname: parsed.pathname,
      username: parsed.username, password: parsed.password }).url;
  },
});

async function authenticate(effect) {
  connection?.abort();
  const controller = new AbortController();
  connection = controller;
  let ready = false;
  try {
    // A journal namespace change ends the old subscription; the authenticated
    // connection observes a fresh snapshot and binds the new namespace.
    while (!disposed && connection === controller && !controller.signal.aborted) await observeConnection({
      request: (url, signal) => request(url, { signal }),
      fetchEvents: (url, signal) => fetch(url, { signal, credentials: 'same-origin' }),
      signal: controller.signal, ownership: requestScope,
      sequence: () => publication.sequence instanceof JsonNumber ? publication.sequence.source : publication.sequence,
      snapshot(body) {
        if (!snapshot(body, publication.namespace, true, effect.ticket))
          throw Object.assign(new Error('The authentication snapshot is not admitted for this browser source.'), { status: 403, requestScope: requestScope() });
      },
      ready() {
        if (ready) return;
        ready = true; dispatch({ type: 'authenticated', ticket: effect.ticket, ok: true, value: null });
      },
      notice(value) { dispatch({ type: 'stream', value }); return true; },
      current: () => !disposed && connection === controller && !controller.signal.aborted,
      namespace: () => publication.namespace,
      refreshNeeded(notice) {
        return publicationEvent('refresh', { source_namespace: notice.namespace,
          source_sequence: notice.sequence, sources_fresh: sourceFresh, connection: state.services.connection });
      },
    });
  } catch (error) {
    // DEFENSE: Superseded fetches report AbortError after a newer connection owns the browser.
    if (controller.signal.aborted || connection !== controller) return;
    // DEFENSE: a state read or SSE open may fail after a command installed a newer cursor.
    if (error.requestScope && !ownsRequestFailure(error.requestScope)) return;
    sourceFresh = false;
    const revoked = authorizationRevoked(error);
    dispatch(ready || revoked ? { type: 'disconnected', ticket: effect.ticket, error: error.message, revoked }
      : { type: 'authenticated', ticket: effect.ticket, ok: false, error: error.message });
  }
}
// The semantic surface declares every admissible destination; native drag only
// supplies the observed target to that element's Place gesture.
let draggedCard = null;
surface.addEventListener('keydown', event => {
  if (event.key !== 'Escape') return;
  for (const node of surface.querySelectorAll('[data-help]:hover,[data-help]:focus-visible')) node.setAttribute('data-help-dismissed', '');
});
for (const name of ['pointerout', 'focusout']) surface.addEventListener(name, event => {
  const node = event.target.closest?.('[data-help-dismissed]');
  if (node && !node.contains(event.relatedTarget)) node.removeAttribute('data-help-dismissed');
});
surface.addEventListener('dragstart', event => {
  const node = event.target.closest?.('[data-card-id][draggable="true"]');
  const record = node && renderer.records.get(node.dataset.key);
  if (!record || !admitted(record.generation)) return;
  draggedCard = record;
  event.dataTransfer.setData('application/x-selvedge-card', node.dataset.cardId);
  event.dataTransfer.effectAllowed = 'move';
});
surface.addEventListener('dragover', event => {
  const target = event.target.closest?.('[data-drop-target]');
  if (draggedCard && target && draggedCard.metadata.placements.some(value => value.target === target.dataset.dropTarget)) event.preventDefault();
});
surface.addEventListener('drop', event => {
  const source = draggedCard; draggedCard = null;
  const target = event.target.closest?.('[data-drop-target]');
  if (!source || !target || !admitted(source.generation)) return;
  const placement = source.metadata.placements.find(value => value.target === target.dataset.dropTarget);
  if (placement) { event.preventDefault(); dispatch({ ...placement.action, value: placement.target }); }
});
surface.addEventListener('dragend', () => { draggedCard = null; });

async function completeCommand(effect) {
  const namespace = publication.namespace;
  try {
    const value = await requestCommand(effect.command);
    if (publication.namespace === namespace && value !== undefined)
      dispatch({ type: 'completed', ticket: effect.ticket, ok: true, value });
  } catch (error) {
    // DEFENSE: The server may have committed a command whose HTTP reply was lost.
    // Preserve its ticket and duplicate protection instead of reporting rejection.
    if (publication.namespace === namespace)
      dispatch({ type: 'completion_failed', ticket: effect.ticket, error: error.message, body: error.body ?? null });
  }
}

async function settled(type, ticket, work) {
  const namespace = publication.namespace;
  try {
    const value = await work();
    if (publication.namespace === namespace) dispatch({ type, ticket, ok: true, value });
  }
  catch (error) {
    // DEFENSE: Network and browser resource operations fail through their matching completion ticket.
    if (publication.namespace === namespace) dispatch({ type, ticket, ok: false, error: error.message });
  }
}
async function assessCommand(effect) {
  const namespace = publication.namespace;
  const key = ticketKey(effect.request.editor);
  assessments.get(key)?.abort();
  const controller = new AbortController();
  assessments.set(key, controller);
  try {
    const value = await post('/api/assess', effect.request, controller.signal);
    if (publication.namespace === namespace) dispatch({ type: 'command_assessed', ticket: effect.ticket, ok: true, value });
  } catch (error) {
    // DEFENSE: A newer draft assessment or page teardown cancels this superseded request.
    if (controller.signal.aborted || publication.namespace !== namespace) return;
    dispatch({ type: 'command_assessed', ticket: effect.ticket, ok: false, error: error.message });
  } finally {
    if (assessments.get(key) === controller) assessments.delete(key);
  }
}
async function execute(effect) {
  const namespace = publication.namespace;
  const current = () => publication.namespace === namespace;
  const emit = input => { if (current()) dispatch(input); };
  switch (effect.type) {
    case 'authenticate': return authenticate(effect);
    case 'schedule_reconnect': {
      const timer = setTimeout(() => { timers.delete(timer); dispatch({ type: 'retry_connection', ticket: effect.ticket }); }, Number(effect.milliseconds));
      timers.add(timer); return;
    }
    case 'command': return completeCommand(effect);
    case 'invalidate_source':
      world = null; sourceFresh = false; retireDocumentViews();
      publication = publicationEvent('invalidate'); render(); return;
    case 'assess_command': return assessCommand(effect);
    case 'save_appearance':
      try { localStorage.setItem('selvedge-appearance', effect.value); }
      // DEFENSE: Browser privacy settings or storage quotas can reject a local preference write.
      catch (error) { emit({ type: 'storage_problem', message: `无法保存外观设置：${error.message}` }); }
      return;
    case 'persist_model_preference':
      try { localStorage.setItem('selvedge-model-preference', stringifyJson({ profile: effect.profile, reasoning: effect.reasoning })); }
      // DEFENSE: A rejected preference write must not undo the already accepted model choice.
      catch (error) { emit({ type: 'storage_problem', message: `无法保存模型偏好：${error.message}` }); }
      return;
    case 'upload': {
      const controller = new AbortController(); transfers.set(ticketKey(effect.ticket), controller);
      const file = files.get(effect.file.handle);
      await settled('uploaded', effect.ticket, async () => {
        const body = await request(`/api/board/attachments?name=${encodeURIComponent(file.name)}`,
          { method: 'POST', body: file, signal: controller.signal });
        return body.result;
      });
      transfers.delete(ticketKey(effect.ticket)); return;
    }
    case 'abort_upload': transfers.get(ticketKey(effect.ticket))?.abort(); return;
    case 'skill_catalog': {
      try {
        const body = await post('/api/browser/observation', taskObservation(effect, { kind: 'skill-catalog', workspace: effect.workspace }));
        if (body.ok) emit({ type: 'skill_catalog', editor: effect.editor, ticket: effect.ticket, skills: body.skills });
        else emit({ type: 'skill_catalog_failed', editor: effect.editor, ticket: effect.ticket, error: body.error });
      } catch (error) {
        // DEFENSE: A workspace catalog observation may fail or change after its requested editor is closed.
        emit({ type: 'skill_catalog_failed', editor: effect.editor, ticket: effect.ticket, error: error.message });
      }
      return;
    }
    case 'observe_directories': return settled('directories_completed', effect.ticket, async () => {
      const body = await post('/api/browser/observation', taskObservation(effect, { kind: 'directories', workspace: effect.workspace }));
      if (body.ok === false) throw new Error(body.error);
      return body;
    });
    case 'workspace_git': return settled('workspace_git_completed', effect.ticket, async () => {
      const body = await post('/api/browser/observation', taskObservation(effect, { kind: 'workspace-git', primary: effect.primary }));
      if (body.ok === false) throw new Error(body.error);
      return body.available;
    });
    case 'list_directory': return settled('directory_listed', effect.ticket, async () => {
      return post('/api/browser/observation', taskObservation(effect, { kind: 'browse-directories', path: effect.path }));
    });
    case 'preview': return settled('previewed', effect.ticket, async () => {
      const blob = await request(`/api/board/attachments/${encodeURIComponent(effect.file.id)}`, {}, true);
      const url = URL.createObjectURL(blob);
      if (current()) resources.add(url); else URL.revokeObjectURL(url);
      return url;
    });
    case 'release_preview': URL.revokeObjectURL(effect.url); resources.delete(effect.url); return;
    case 'download': {
      try {
        const blob = await request(`/api/board/attachments/${encodeURIComponent(effect.file.id)}`, {}, true);
        if (!current()) return;
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a'); link.href = url; link.download = effect.file.name;
        link.click(); setTimeout(() => URL.revokeObjectURL(url), 0);
      } catch (error) {
        // DEFENSE: A file can disappear or a download connection can fail without invalidating the rendered page.
        emit({ type: 'native_failed', error: `Download failed: ${error.message}` });
      }
      return;
    }
    case 'focus': {
      pendingFocus = { effect, namespace: publication.namespace, attempt: ++focusRequest };
      retryFocus();
      return;
    }
    case 'follow_latest': {
      const node = renderer.resolveTarget(effect.key, { modal: false });
      if (node) readingStep(node.dataset.key, node, 'follow');
      return;
    }
    case 'scroll_to_message': {
      pendingHistoryLocation = { ...effect, namespace: publication.namespace };
      retryHistoryLocation();
      return;
    }
    case 'selection_bytes': applyByteSelection(renderer.resolveTarget(effect.key), integral(effect.start), integral(effect.end)); return;
    case 'clipboard': await navigator.clipboard.writeText(effect.text); return;
    case 'audio_login': return audio.execute('BeginAudioLogin', effect);
    case 'audio_capabilities': return audio.execute('LoadCapabilities', effect);
    case 'record_audio': return audio.execute('Record', { ...effect, ticket: integral(effect.ticket), owner: effect.editor });
    case 'transcribe_audio': return audio.execute('Transcribe', { ...effect, ticket: integral(effect.ticket) });
    case 'release_audio': return audio.execute('Release', { ...effect, ticket: integral(effect.ticket) });
    case 'voice_create_task': return audio.execute('CreateTask', { ...effect, ticket: integral(effect.ticket) });
    case 'connect_voice': return audio.execute('ConnectVoice', { ...effect, ticket: integral(effect.ticket), task: integral(effect.task_id) });
    case 'voice_input_mute': return audio.execute('SetInputMute', { ...effect, ticket: integral(effect.ticket) });
    case 'voice_output_mute': return audio.execute('SetOutputMute', { ...effect, ticket: integral(effect.ticket) });
    case 'interactive_parse': {
      const timer = setTimeout(() => { timers.delete(timer);
        emit({ type: 'interactive', input: { type: 'continue', owner: effect.owner } });
      }, 0); timers.add(timer); return;
    }
    case 'interactive_load': {
      let saved;
      try { saved = storage.load(effect.storage_key); }
      catch (error) {
        // DEFENSE: Browser storage can be unavailable; preserve the entry and report the failed observation.
        emit({ type: 'interactive', input: { type: 'storage', owner: effect.owner,
          revision: effect.revision, ok: false, message: error.message } }); return;
      }
      emit({ type: 'interactive', input: { type: 'restore', owner: effect.owner,
        definition: effect.definition, revision: effect.revision,
        present: saved.present, payload: saved.value, settled: true } }); return;
    }
    case 'interactive_save': storage.save(effect.storage_key, effect.payload, (ok, message) =>
      emit({ type: 'interactive', input: { type: 'storage', owner: effect.owner, revision: effect.revision, ok, message } })); return;
    case 'interactive_remove': {
      try { storage.remove(effect.storage_key); }
      catch (error) {
        // DEFENSE: Browser storage permissions can reject removal of an invalid saved entry.
        if (error.name !== 'SecurityError') throw error;
        emit({ type: 'interactive', input: { type: 'storage', owner: effect.owner,
          revision: effect.revision, ok: false, message: error.message } });
      }
      return;
    }
    case 'interactive_clipboard': {
      let ok = true, message = '';
      try { await navigator.clipboard.writeText(effect.text); }
      catch (error) {
        // DEFENSE: Clipboard permission and browser activation requirements can reject a declared copy effect.
        ok = false; message = error.message;
      }
      emit({ type: 'interactive', input: { type: 'feedback', owner: effect.owner,
        path: effect.path, ticket: effect.ticket, ok, message } }); return;
    }
    case 'interactive_open_url': {
      const url = safeHref(effect.url, document.baseURI);
      if (url !== null) window.open(url, '_blank', 'noopener,noreferrer');
      emit({ type: 'interactive', input: { type: 'feedback', owner: effect.owner,
        path: effect.path, ticket: effect.ticket, ok: url !== null, message: url === null ? 'Navigation URL is not allowed' : '' } }); return;
    }
    case 'restore_field_buffer': renderer.restoreField(effect.key, effect.value); return;
    default: throw new RangeError(`Unknown browser effect: ${effect.type}`);
  }
}

const selections = new WeakMap();
function selectionChanged() {
  const node = document.activeElement;
  if (!node || typeof node.selectionStart !== 'number') return;
  const record = Array.from(renderer.records.values()).find(record => record.node === node);
  const binding = record?.events.find(binding => binding.kind === 'value' && binding.action.op === 'element');
  if (!binding || !record.metadata.selection_enabled || !admitted(record.generation)) return;
  const selection = observedSelection(node, renderer.composing.has(node));
  const observed = stringifyJson(selection);
  if (selections.get(node) === observed) return;
  selections.set(node, observed);
  dispatch({ ...binding.action, gesture: 'selection', value: selection });
}
document.addEventListener('selectionchange', selectionChanged);

window.addEventListener('pagehide', () => {
  disposed = true; document.removeEventListener('selectionchange', selectionChanged); document.removeEventListener('keydown', dismiss); document.removeEventListener('pointerdown', dismiss); connection?.abort(); audio.dispose(); motion.dispose(); physical.dispose(); renderer.dispose(); storage.flush();
  clearInterval(clockRefresh); document.removeEventListener('visibilitychange', refreshClock);
  for (const timer of timers) clearTimeout(timer);
  for (const entry of codeBlocks.values()) for (const physical of entry.views.values()) physical.renderer?.dispose();
  for (const controller of transfers.values()) controller.abort();
  for (const controller of assessments.values()) controller.abort();
  for (const node of readingMeasurements.keys()) retireReadingMeasurement(node);
  pendingHistoryLocation = null;
  window.removeEventListener('pointerup', endReadingPointer, true);
  window.removeEventListener('pointercancel', endReadingPointer, true);
  for (const resource of resources) URL.revokeObjectURL(resource);
  if (layoutFrame !== null) cancelAnimationFrame(layoutFrame);
}, { once: true });
window.addEventListener('focus', () => audio.focus());
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => refreshPhysical().catch(fatal));
clockRefresh = setInterval(refreshClock, 60_000);
document.addEventListener('visibilitychange', () => { refreshClock(); retryFocus(); });
refreshClock();
await refreshPhysical().catch(fatal);
try {
  const restoredAppearance = localStorage.getItem('selvedge-appearance');
  if (restoredAppearance !== null) dispatch({ type: 'appearance_restored', value: restoredAppearance });
  const restoredModel = localStorage.getItem('selvedge-model-preference');
  if (restoredModel !== null) dispatch({ type: 'model_preference_restored', value: restoredModel });
}
// DEFENSE: Storage access can be disabled while the authenticated task service remains available.
catch (error) { dispatch({ type: 'storage_problem', message: `无法读取本地设置：${error.message}` }); }
dispatch({ type: 'connect' });
