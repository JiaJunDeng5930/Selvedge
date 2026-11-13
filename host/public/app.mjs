import { boundary } from './model-boundary.mjs';
import { browser, interaction, presentNative } from './browser-model-boundary.mjs';
import { JsonNumber, parseJson, stringifyJson } from './json-tokens.mjs';
import { Renderer, filesFromEvent } from './renderer.mjs';
import { editorKeyboard, applyByteSelection, selectingRadioGroup, radioTabTargets } from './keyboard.mjs';
import { observeConnection } from './connection.mjs';
import { AudioRuntime } from './audio.mjs';
import { ChatGPTLogin } from './chatgpt-login.mjs';
import { InteractiveSnapshotStorage } from './interactive-storage.mjs';
import { createEditorRepairPlacement, createLayoutRevealer, revealAndFocus, revealInScrollport } from './layout-reveal.mjs';
import { PresentationMotion } from './presentation-motion.mjs';
import { safeHref, scheduleDisplay, cancelDisplay } from './markdown.mjs';
import { findHistoryRange, firstRangeRect } from './history-location.mjs';
import { createPhysicalMeasurer } from './physical-measurement.mjs';
import { installModelPickerPreview } from './model-picker.mjs';

const surface = document.getElementById('surface');
installModelPickerPreview(surface);
const announcements = document.getElementById('announcements');
const updateStatus = document.getElementById('selvedge-update-status');
const documentRelease = document.querySelector('meta[name="selvedge-release"]')?.content;
const updateSessionKey = 'selvedge-update-session';
const files = new Map();
const transfers = new Map();
const assessments = new Map();
const candidateAssessments = new Map();
let drainingCandidates = false;
const resources = new Set();
const timers = new Set();
const readings = new Map();
const readingMeasurements = new Map();
const readingPointers = new Map();
const readingLayouts = new WeakMap();
const readingVisits = new WeakMap();
const readingBlocks = new WeakMap();
const restoredReadingOffsets = new WeakMap();
const codeBlocks = new Map();
const storagePolicy = interaction('interactive_storage_policy');
const storage = new InteractiveSnapshotStorage({ ...storagePolicy,
  maximumDocuments: Number(storagePolicy.maximumDocuments instanceof JsonNumber ? storagePolicy.maximumDocuments.source : storagePolicy.maximumDocuments),
  maximumBytes: Number(storagePolicy.maximumBytes instanceof JsonNumber ? storagePolicy.maximumBytes.source : storagePolicy.maximumBytes) });
const activeModal = () => renderer.modal;
const reveal = createLayoutRevealer(surface, activeModal);
const editorRepair = createEditorRepairPlacement(activeModal);
const motion = new PresentationMotion(surface, activeModal);
let state = interaction('initial');
let world = null;
let publication = { generation: 0, phase: 'awaiting', namespace: '', sequence: 0,
  displayed_generation: null, native_displayed_generation: null };
let environment = null;
let measuring = null;
let measureAgain = false;
let renderAfterMeasurement = null;
let measurementFrame = null;
let measurementTask = null;
let connection = null;
let disposed = false;
let clockRefresh = null;
let sourceFresh = false;
let layoutFrame = null;
let readingLayoutScheduled = false;
let pendingHistoryLocation = null;
let historyLocation = null;
let searchResultsPosition = null;
let boardTrack = null;
let boardFirstLane = null;
let boardScrollControls = null;
let boardHasOverflow = false;
const boardTrackResize = new ResizeObserver(updateBoardScroll);
let focusRequest = 0;
let pendingFocus = null;
let suspendedFocus = null;
let updateStorageProblem = '';
const ticketKey = value => stringifyJson(value);
const integral = value => BigInt(value instanceof JsonNumber ? value.source : value);
const readDeadline = () => AbortSignal.timeout(20_000);

function randomBrowserIdentifier() {
  // getRandomValues is available on private HTTP origins as well as HTTPS.
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
}

function showUpdateStatus({ status, operations, message }) {
  let text = '';
  switch (status) {
    case 'draining':
      text = operations.length ? `正在等待操作完成后更新：${operations.join('、')}` : '正在等待操作完成后更新…';
      break;
    case 'switching': text = '正在切换到新版本…'; break;
    case 'failed': text = `更新失败：${message}`; break;
  }
  updateStatus.textContent = updateStorageProblem || text;
}

function reloadForRelease(release) {
  if (!documentRelease || !release || release === documentRelease) return false;
  if (publication.namespace) {
    const session = interaction('update_session', { state });
    try {
      sessionStorage.setItem(updateSessionKey, stringifyJson({ namespace: publication.namespace, session }));
    } catch (error) {
      // DEFENSE: Browser settings or storage quota can prevent saving this tab's drafts.
      updateStorageProblem = `无法保存更新前的草稿，当前页面保持打开：${error.message}`;
      showUpdateStatus({ status: 'idle' });
      return false;
    }
  }
  connection?.abort();
  window.location.reload();
  return true;
}

function restoreUpdateSession() {
  try {
    const stored = sessionStorage.getItem(updateSessionKey);
    if (stored === null) return;
    const { namespace, session } = parseJson(stored);
    if (namespace === publication.namespace) {
      state = interaction('restore_update_session', { state, world, checkpoint: session });
    }
    sessionStorage.removeItem(updateSessionKey);
  } catch (error) {
    // DEFENSE: Browser storage can be disabled or its checkpoint can be unreadable.
    updateStorageProblem = `无法恢复更新前的草稿：${error.message}`;
    showUpdateStatus({ status: 'idle' });
  }
}

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
    // The previous page may not understand the new release's snapshot format.
    if (url === '/api/browser/state' && response.ok && reloadForRelease(response.headers.get('x-selvedge-release'))) return null;
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
  return generation !== null && generation !== undefined &&
    publicationEvent('native_admit', { receipt_generation: generation });
}
function prefixAdmitted(generation) {
  return generation !== null && generation !== undefined &&
    publicationEvent('admit', { receipt_generation: generation });
}
function sameGeneration(left, right) {
  return left === right || left instanceof JsonNumber && right instanceof JsonNumber && left.source === right.source;
}
function snapshot(body, expected = publication.namespace, authenticating = false, authenticationTicket) {
  const receipt = browser('snapshot', { ...publication, expected_namespace: expected, incoming_namespace: body.namespace,
    incoming_sequence: body.sequence, authenticating,
    sources_fresh: sourceFresh,
    ...(authenticating ? { authentication_ticket: authenticationTicket, connection: state.services.connection } : {}) });
  sourceFresh = receipt.sources_fresh;
  if (!receipt.accepted) return receipt.authenticated;
  if (!receipt.install_world) return true;
  const firstSnapshot = world === null;
  if (body.namespace !== publication.namespace) retireDocumentViews();
  world = body.program;
  publication = publicationEvent('observe', { observed_namespace: body.namespace, observed_sequence: body.sequence });
  if (firstSnapshot && documentRelease) restoreUpdateSession();
  dispatch({ type: 'snapshot' });
  return true;
}
function retireDocumentViews() {
  for (const entry of codeBlocks.values()) for (const physical of entry.views.values()) physical.renderer?.dispose();
  codeBlocks.clear(); readings.clear(); files.clear(); renderer.reset();
  for (const node of readingMeasurements.keys()) retireReadingMeasurement(node);
  retireHistoryLocation(); pendingFocus = null; suspendedFocus = null; focusRequest++;
  searchResultsPosition = null;
  suspendedPrefixFocus = null;
  for (const controller of assessments.values()) controller.abort();
  assessments.clear();
  candidateAssessments.clear();
  for (const resource of resources) URL.revokeObjectURL(resource);
  resources.clear();
}
function fatal(error) {
  publication = publicationEvent('failure', { reason: error.message });
  render();
}
function synchronizeNativeAuthority() {
  const inert = !publicationEvent('native_ready');
  const wasInert = surface.inert;
  if (inert && !surface.inert) {
    const node = document.activeElement;
    suspendedFocus = surface.contains(node) ? { node, attempt: focusRequest } : null;
  }
  if (surface.inert !== inert) surface.inert = inert;
  // Native modal dialogs escape ancestor inertness; apply the same receipt to
  // those real DOM roots as well as to the ordinary document tree.
  if (inert || wasInert)
    for (const dialog of surface.querySelectorAll('dialog')) if (dialog.inert !== inert) dialog.inert = inert;
  if (!inert && suspendedFocus) {
    const retained = suspendedFocus; suspendedFocus = null;
    // Toggling native inertness can blur an unchanged editor. Preserve that
    // physical focus unless another focus request or replacement superseded it.
    if (retained.attempt === focusRequest && retained.node.isConnected &&
        !retained.node.matches(':disabled,[aria-disabled="true"]') &&
        document.activeElement === document.body) {
      retained.node.focus({ preventScroll: true });
      if (retained.finishComposition) queueMicrotask(retained.finishComposition);
    }
  }
}
let suspendedPrefixFocus = null;
function synchronizePrefixActions() {
  if (renderer.prefixActions.size) renderer.synchronizePrefixActions(!prefixAdmitted(renderer.generation));
}
function synchronizePrefixAuthority() {
  if (!renderer.prefixFields.size && !renderer.prefixActions.size && !suspendedPrefixFocus) return;
  const inert = !prefixAdmitted(renderer.generation);
  const node = document.activeElement;
  if (inert && renderer.prefixFields.has(node) && !node.inert)
    suspendedPrefixFocus = { node, attempt: focusRequest };
  renderer.synchronizePrefixFields(inert);
  renderer.synchronizePrefixActions(inert);
  if (!inert && suspendedPrefixFocus) {
    const retained = suspendedPrefixFocus;
    suspendedPrefixFocus = null;
    if (retained.attempt === focusRequest && renderer.prefixFields.has(retained.node) &&
        !retained.node.disabled && document.activeElement === document.body)
      retained.node.focus({ preventScroll: true });
  }
}
function renderRecovery(reason) {
  surface.inert = false;
  renderer.render(browser('recovery', { root_font_size_milli: physical.viewport().root_font_size_milli,
    generation: publication.generation, reason }), publication.generation);
}
function dispatch(input) {
  if (disposed) return;
  const decision = interaction('step', { state, input, world, environment, generation: publication.generation,
    namespace: publication.namespace, now: BigInt(Math.floor(Date.now() / 1000)),
    displayed_generation: publication.displayed_generation, native_displayed_generation: publication.native_displayed_generation,
    semantic_lagged: publicationEvent('semantic_pending') });
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
  if (decision.publication_event !== 'keep')
    render(decision.native_stream ? 'stream' : decision.native_picker ? 'picker' : null);
  for (const effect of decision.effects) execute(effect).catch(fatal);
  return decision;
}
function retryFocus() {
  const pending = pendingFocus;
  if (!pending) return;
  // DEFENSE: a native focus request can outlive another focus or its journal.
  if (pending.attempt !== focusRequest || pending.namespace !== publication.namespace) { pendingFocus = null; return; }
  if (document.visibilityState !== 'visible' || !admitted(renderer.generation)) return;
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
function render(local = null) {
  if (disposed) return;
  const recovery = publicationEvent('recovery');
  if (recovery !== null) { renderRecovery(recovery); return; }
  if (!environment) return;
  try { present(local); }
  catch (error) {
    // DEFENSE: Native DOM updates can fail during a scene change. Keep the
    // same recovery action available as for a failed physical observation.
    fatal(error);
  }
}
function renderDocument(plan, generation) {
  const selector = 'main > [data-page-region="history-results"]';
  const previous = surface.querySelector(selector);
  const scrollport = previous?.parentElement;
  const offset = scrollport?.scrollTop;
  renderer.render(plan, generation);
  const track = surface.querySelector('[data-page-region="board-stages"]');
  const firstLane = track?.firstElementChild ?? null;
  const controls = track?.parentElement.querySelector('[data-board-scroll-controls]') ?? null;
  if (controls !== boardScrollControls || track !== boardTrack) {
    boardScrollControls = controls;
    for (const button of controls?.querySelectorAll('[data-board-scroll]') ?? [])
      button.setAttribute('aria-controls', track.id);
  }
  if (track !== boardTrack || firstLane !== boardFirstLane) {
    boardTrackResize.disconnect();
    if (track !== boardTrack) boardHasOverflow = false;
    boardTrack = track;
    boardFirstLane = firstLane;
    if (track) boardTrackResize.observe(track);
    if (firstLane) boardTrackResize.observe(firstLane);
  }
  if (controls && boardHasOverflow) controls.hidden = false;
  const current = surface.querySelector(selector);
  if (previous === current) return;
  if (previous) {
    // The workspace keeps its main scrollport mounted across route changes.
    searchResultsPosition = { key: previous.dataset.key, offset };
    scrollport.scrollTop = 0;
  }
  if (current) current.parentElement.scrollTop =
    current.dataset.key === searchResultsPosition?.key ? searchResultsPosition.offset : 0;
}
function updateBoardScroll() {
  if (!boardTrack || !boardScrollControls) return;
  const overflow = boardTrack.scrollWidth - boardTrack.clientWidth;
  boardHasOverflow = overflow > 1;
  boardScrollControls.hidden = !boardHasOverflow;
  for (const button of boardScrollControls.querySelectorAll('[data-board-scroll]')) {
    const available = button.dataset.boardScroll === 'next'
      ? boardTrack.scrollLeft < overflow - 1
      : boardTrack.scrollLeft > 1;
    button.setAttribute('aria-disabled', String(!available));
  }
}
function scrollBoard(direction) {
  boardTrack.scrollBy({ left: direction * boardTrack.clientWidth / 2 });
}
function present(local) {
  surface.dataset.displayPending = String(publicationEvent('pending'));
  const measuringDocument = measuring && renderer.document;
  const deferRender = () => {
    if (publication.native_displayed_generation === null) synchronizeNativeAuthority();
    synchronizePrefixActions();
    // A single transaction can still publish its local update after the
    // measurement. Multiple transactions require the complete current view.
    renderAfterMeasurement = { local: renderAfterMeasurement ? null : local };
    measureAgain = true;
  };
  // A local update can use the last measured environment if its base is still
  // mounted. Any older in-flight layout observation then fails its generation check.
  if (measuringDocument && (!local || renderAfterMeasurement ||
      !sameGeneration(renderer.generation, publication.native_displayed_generation))) {
    deferRender(); return;
  }
  const generation = publication.generation;
  const materialize = ops => presentNative(local, state, world, environment, generation, ops);
  const directlyPresented = local === 'picker' ? renderer.renderPicker(materialize, generation)
    : local === 'stream' && renderer.renderStream(materialize, generation);
  const streamed = local === 'stream' && directlyPresented;
  if (!directlyPresented) {
    if (measuringDocument) { deferRender(); return; }
    const plan = interaction('observe', { state, world, environment, generation,
      namespace: publication.namespace, now: BigInt(Math.floor(Date.now() / 1000)), displayed_generation: publication.displayed_generation, semantic_lagged: publicationEvent('semantic_pending') });
    surface.dataset.displayPending = String(publicationEvent('pending'));
    renderDocument(plan, generation);
  }
  surface.dataset.sourcesFresh = String(sourceFresh);
  if (!streamed) physical.refresh();
  if (!renderer.document.measurement_pending) {
    publication = publicationEvent('document', { receipt_generation: generation });
    if (!streamed) {
      synchronizeNativeAuthority();
      retryFocus();
    }
    const publishPrefix = caughtUp => {
      // A newer DOM publication also waits for its own parser receipt.
      if (!caughtUp || disposed) return;
      if (!sameGeneration(generation, publication.generation)) return;
      publication = publicationEvent('publish', { receipt_generation: generation });
      synchronizePrefixAuthority();
      // The receipt changes input authority, not the compiled state/world/environment.
      // Keep the same DOM and finish the native work that was waiting for publication.
      surface.dataset.displayPending = String(publicationEvent('pending'));
      if (!streamed && publicationEvent('ready')) {
        renderer.refreshNativeTargets();
        // Document-derived targets are available after their parsers catch up.
        reveal();
      }
      scheduleReadingLayout(); retryFocus();
    };
    if (renderer.isCaughtUp()) publishPrefix(true);
    else {
      synchronizePrefixAuthority();
      renderer.whenCaughtUp().then(publishPrefix).catch(fatal);
    }
  } else synchronizePrefixActions();
  if (!streamed) { reveal(); editorRepair.refresh(); motion.refresh(); retryHistoryLocation(); layoutReading(); }
}
function schedulePhysicalRefresh() {
  if (disposed || measurementFrame !== null || measurementTask !== null) return;
  // Publish the current document before measuring its new physical layout.
  measurementFrame = requestAnimationFrame(() => {
    measurementFrame = null;
    measurementTask = setTimeout(() => {
      measurementTask = null;
      refreshPhysical().catch(fatal);
    }, 0);
  });
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
      for (const update of browser('responsive_rows', { rows: observations.responsive_rows })) {
        const row = renderer.target(update.key);
        if (row.style.getPropertyValue('flex-direction') !== update.direction) row.style.setProperty('flex-direction', update.direction);
        if (row.dataset.nativeRowDirection !== update.direction) row.dataset.nativeRowDirection = update.direction;
        if (update.supporting_form !== undefined && row.dataset.supportingForm !== update.supporting_form)
          row.dataset.supportingForm = update.supporting_form;
      }
      if (changed) {
        environment = next;
        dispatch({ type: 'environment_observed' });
      }
    } while (measureAgain && !disposed);
  })();
  try { await measuring; } finally {
    measuring = null;
    if (renderAfterMeasurement && !disposed) {
      const pending = renderAfterMeasurement;
      renderAfterMeasurement = null;
      render(pending.local);
    }
  }
}
function observedSelection(node, composing = false) {
  const encode = value => new TextEncoder().encode(value).length;
  return { start: encode(node.value.slice(0, node.selectionStart ?? node.value.length)),
    end: encode(node.value.slice(0, node.selectionEnd ?? node.value.length)), direction: node.selectionDirection, composing };
}
function registerFiles(action, selected) {
  for (const file of selected) {
    const handle = randomBrowserIdentifier(); files.set(handle, file);
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
    if (event.target !== node) return;
    if (node.matches('input,textarea,select') &&
        node.closest('dialog[data-semantic-key="settings-configuration-editor"] [data-surface-role="dialog-body"]')) {
      // Native focus can leave the lower edge of an already exposed field clipped.
      revealInScrollport(node);
    }
    if (typeof node.selectionStart !== 'number') return;
    const record = renderer.records.get(key);
    const binding = record?.events.find(binding => binding.kind === 'value' && binding.action.op === 'element');
    if (!binding || !record.metadata.selection_enabled || !admitted(record.generation)) return;
    dispatch({ ...renderer.input(record, binding.action), gesture: 'selection',
      value: { ...observedSelection(node, renderer.composing.has(node)), refocus: true } });
  },
  composition(event, key, node) {
    const record = renderer.records.get(key);
    const binding = record?.events.find(binding => binding.kind === 'value' && binding.action.op === 'element');
    if (binding && record.metadata.selection_enabled && admitted(record.generation))
      dispatch({ ...renderer.input(record, binding.action), gesture: 'selection', value: observedSelection(node, true) });
  },
  blur(event, key, node) {
    if (event.target !== node || typeof node.selectionStart !== 'number') return;
    const record = renderer.records.get(key);
    const binding = record?.events.find(binding => binding.kind === 'value' && binding.action.op === 'element');
    if (!binding || !record.metadata.selection_enabled || !admitted(record.generation)) return;
    dispatch({ ...renderer.input(record, binding.action), gesture: 'selection',
      value: { ...observedSelection(node, renderer.composing.has(node)), blur: true } });
  },
  event(binding, event, key, node, generation) {
    if (binding.kind === 'retry_render') {
      event.preventDefault(); publication = publicationEvent('retry');
      refreshPhysical().then(render).catch(fatal); return;
    }
    if (!admitted(generation)) {
      // DEFENSE: Making the surface inert for measurement can commit the focused
      // IME input. Deliver that observation when the same field owns input again.
      if (event.type === 'compositionend' && binding.kind === 'value' && suspendedFocus?.node === node) {
        const session = renderer.records.get(key)?.fieldSession;
        const value = node.value;
        suspendedFocus.finishComposition = () => {
          const record = renderer.records.get(key);
          if (!session || record?.node !== node || record.fieldSession?.identity !== session.identity ||
              record.fieldSession.canonical !== session.canonical || node.value !== value ||
              !admitted(record.generation)) return;
          const current = record.events.find(candidate => candidate.kind === 'value' && candidate.event === binding.event);
          if (current) renderer.callbacks.event({ ...current, action: renderer.input(record, current.action) },
            event, key, node, record.generation);
        };
      }
      return;
    }
    if ((node.dataset.prefixField === 'true' || node.dataset.prefixAction === 'true') && !prefixAdmitted(generation)) {
      if (node.dataset.prefixField === 'true') renderer.restorePrefixField(key);
      else event.preventDefault();
      return;
    }
    if (binding.kind === 'files') {
      registerFiles(binding.action, filesFromEvent(event, node));
      if (node.type === 'file') node.value = '';
    }
    else if (binding.kind === 'value') {
      const publishReading = binding.event === 'change' && node.matches('select') &&
        node.closest('[data-interactive-component="select"]') ? holdAuthoredReading(node) : null;
      dispatch({ ...binding.action, value: node.value,
        raw: node.value, selection: observedSelection(node, event.isComposing || renderer.composing.has(node)) });
      publishReading?.();
    }
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
          namespace: publication.namespace, displayed_generation: publication.displayed_generation,
          native_displayed_generation: publication.native_displayed_generation, now: BigInt(Math.floor(Date.now() / 1000)) })) {
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
    const radioArrow = node === event.target && keyboard.unmodified && !composing &&
      ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key) ? selectingRadioGroup(node) : null;
    if (dialog && (event.key === 'Tab' || radioArrow)) {
      // DEFENSE: Controls inside a closed disclosure can still report visible layout rectangles.
      const candidates = Array.from(dialog.querySelectorAll('button,a[href],input,textarea,select,details > summary,[tabindex]')).filter(target =>
        target.tabIndex >= 0 && !target.matches(':disabled,[aria-disabled="true"]') &&
        !target.closest('[inert],[hidden],details:not([open]) > :not(summary)') &&
        target.getClientRects().length && getComputedStyle(target).visibility !== 'hidden');
      const { targets, current } = radioArrow
        ? { targets: candidates.filter(target => selectingRadioGroup(target) === radioArrow), current: node }
        : radioTabTargets(candidates, event.target);
      const keys = targets.map((_, index) => String(index));
      const backward = radioArrow ? event.key === 'ArrowLeft' || event.key === 'ArrowUp' : event.shiftKey;
      const next = browser('focus_cycle', { current: String(targets.indexOf(current)), targets: keys, backward });
      if (next !== null) {
        event.preventDefault();
        const target = targets[Number(next)];
        target.focus();
        if (radioArrow && target !== current) target.click();
      }
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
    scheduleReadingLayout();
    if (layoutFrame === null) layoutFrame = requestAnimationFrame(() => {
      layoutFrame = null; reveal(); renderer.confineAnchoredLayers();
    });
  },
  codeSource(source, ordinal, text, view) {
    publishCode(browser('code_identity', { source, ordinal }), view, text);
  },
  codePublication({ identity, view, text }) { publishCode(identity, view, text); },
  codeIdentity(source, ordinal) { return browser('code_identity', { source, ordinal }); },
  codeTargets(identity, view) { return browser('code_targets', { identity, view }); },
  interactiveFence(info) {
    return browser('interactive_fence', { raw_info: info, fence_kind: 'fenced', info_complete: true });
  },
  fence(metadata, observed) {
    return dispatch({ type: 'code_observed', origin: metadata.origin, document_key: metadata.document_key,
      epoch: metadata.epoch, revision: observed.inputRevision, ordinal: observed.ordinal,
      fence_kind: observed.kind, info_complete: observed.infoComplete,
      raw_info: observed.info, code_prefix: observed.code, closed: observed.closed,
      input_prefix: observed.inputPrefix })?.fence_admitted;
  },
});

const physical = createPhysicalMeasurer({ surface, onChange() {
  scheduleReadingLayout();
  schedulePhysicalRefresh();
} });

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
          if (!prefixAdmitted(renderer.generation)) return;
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
const readingTop = node => node.getBoundingClientRect().top + node.clientTop;
function readingAnchor(node, identity) {
  return node.querySelector(`[data-reading-identity="${CSS.escape(identity)}"]`);
}
function readingState(key, node) {
  const bound = browser('reading_bind', { generation: new JsonNumber(node.dataset.readerGeneration),
    state: readings.get(readingKey(node)) ?? null });
  readings.set(readingKey(node), bound);
  return bound;
}
function acceptReading(key, node, decision, locationTarget, publishIntent = true) {
  const previous = readings.get(readingKey(node))?.intent ?? 'follow';
  readings.set(readingKey(node), decision.state);
  for (const effect of decision.effects) {
    if (effect.type === 'leave_viewport') {
      if (!locationTarget) retireHistoryLocation(node);
      readingBlocks.delete(node);
      restoredReadingOffsets.delete(node);
      node.scrollTo({ top: node.scrollTop, left: node.scrollLeft, behavior: 'instant' });
    }
    else if (effect.type === 'align_latest') node.scrollTo({ top: node.scrollHeight, behavior: effect.animate ? 'smooth' : 'instant' });
    else if (effect.type === 'reserve_composer') node.style.setProperty('scroll-padding-block-end', effect.clearance);
    else if (effect.type === 'cancel_anchor') retireReadingMeasurement(node);
    else if (effect.type === 'locate_message' && locationTarget) {
      const { target, range } = locationTarget;
      const bounds = (range && firstRangeRect(range)) || target.getBoundingClientRect();
      const clearance = Number.parseFloat(getComputedStyle(node).scrollPaddingBlockStart);
      node.scrollTo({ top: node.scrollTop + bounds.top - readingTop(node) - clearance,
        left: node.scrollLeft, behavior: 'instant' });
      restoredReadingOffsets.set(node, node.scrollTop);
      if (range) locationTarget.offset = (firstRangeRect(range)?.top ?? readingTop(node) + clearance) - readingTop(node);
      observeReadingAnchor(node, decision.state, target);
    }
    else if (effect.type === 'preserve_anchor' && !currentReadingMeasurement(node)) {
      const target = readingAnchor(node, effect.anchor.key);
      if (target) {
        const location = currentHistoryLocation(node);
        const bounds = location?.target === target && location.range && firstRangeRect(location.range);
        const block = readingBlocks.get(node);
        const local = block?.anchor === target && target.contains(block.node) ? block : null;
        node.scrollTop += (bounds?.top ?? (local?.node ?? target).getBoundingClientRect().top) - readingTop(node) -
          (bounds ? location.offset : local?.offset ?? Number(effect.anchor.offset));
        restoredReadingOffsets.set(node, node.scrollTop);
        // Keep the ordinary message bookmark usable after this Range is retired.
        if (bounds) observeReadingAnchor(node, decision.state, target);
      }
    } else if (effect.type === 'measure_anchor') {
      if (currentReadingMeasurement(node)) requestReadingAnchor(key, node);
      else observeReadingAnchor(node, decision.state);
    }
  }
  if (previous === decision.state.intent || node.dataset.readerGeneration === undefined) return;
  const publish = () => {
    if (!node.isConnected || readings.get(readingKey(node))?.intent !== decision.state.intent) return;
    dispatch({ type: 'read_timeline', task: new JsonNumber(node.dataset.taskId),
      generation: new JsonNumber(node.dataset.readerGeneration), intent: decision.state.intent });
  };
  if (publishIntent) publish();
  else return publish;
}
function holdAuthoredReading(node) {
  const reader = node.closest('[data-reading-root="true"]');
  const anchor = node.closest('[data-reading-anchor]');
  if (!reader || !anchor || !reader.contains(anchor)) return;
  const key = reader.dataset.key;
  const state = readingState(key, reader);
  if (state.intent !== 'follow') return;
  // Install the bookmark before the change can alter layout. Publish its
  // intent afterward, so the change retains the generation that admitted it.
  return acceptReading(key, reader, browser('reading', { state, event: 'read_at', anchor: {
    key: anchor.dataset.readingIdentity, offset: String(anchor.getBoundingClientRect().top - readingTop(reader)),
  } }), undefined, false);
}
function observeReadingAnchor(node, state, selected) {
  const top = readingTop(node);
  const anchor = selected ?? Array.from(node.querySelectorAll('[data-reading-anchor]')).find(target => {
    const bounds = target.getBoundingClientRect();
    return bounds.bottom > top && bounds.top < top + node.clientHeight;
  });
  if (!anchor) return;
  const block = selected ? null : Array.from(anchor.querySelectorAll('.physical-markdown > .markdown > [data-stable]')).find(target => {
    const bounds = target.getBoundingClientRect();
    return bounds.bottom > top && bounds.top < top + node.clientHeight &&
      !target.matches('[data-interactive-preview-candidate]:not([data-interactive-active], [data-interactive-preview-failed])');
  });
  // The durable bookmark identifies the message. A retained Markdown block
  // also identifies the visible passage when an earlier widget in that message grows.
  if (block) readingBlocks.set(node, { anchor, node: block, offset: block.getBoundingClientRect().top - top });
  else readingBlocks.delete(node);
  readings.set(readingKey(node), browser('reading', { state, event: 'anchor', anchor: {
    key: anchor.dataset.readingIdentity, offset: String(anchor.getBoundingClientRect().top - top) } }).state);
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
    if (state.intent === 'history') observeReadingAnchor(node, state);
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
const historyHighlight = 'selvedge-history-match';
const historyHighlightMs = 5000;
const sameHistoryVisit = location => location.namespace === publication.namespace &&
  location.navigationGeneration === integral(state.navigation.generation);
const historyReaderOwns = (root, location) => root.dataset.readerGeneration === location.readerGeneration &&
  root.dataset.taskId === location.taskId;
function clearHistoryHighlight(location) {
  CSS.highlights?.delete(historyHighlight);
  location.target.removeAttribute('data-history-match');
  if (location.timer !== undefined) {
    clearTimeout(location.timer);
    timers.delete(location.timer);
    delete location.timer;
  }
}
function retireHistoryLocation(root) {
  const pending = pendingHistoryLocation;
  if (pending && (!root || historyReaderOwns(root, pending))) {
    if (pending.frame != null) cancelDisplay(pending.frame);
    pendingHistoryLocation = null;
  }
  if (historyLocation && (!root || historyLocation.root === root)) {
    clearHistoryHighlight(historyLocation);
    historyLocation = null;
  }
}
function currentHistoryLocation(root) {
  const location = historyLocation;
  // DEFENSE: parsing and layout can outlive the physical reader occurrence.
  if (location && (!sameHistoryVisit(location) || !location.root.isConnected ||
      !location.target.isConnected || !historyReaderOwns(location.root, location) ||
      location.range && !location.target.contains(location.range.startContainer))) {
    clearHistoryHighlight(location);
    historyLocation = null;
  }
  return historyLocation && historyLocation.root === root ? historyLocation : null;
}
function locateHistoryRange(pending, root, target, range) {
  pendingHistoryLocation = null;
  const location = { namespace: pending.namespace, navigationGeneration: pending.navigationGeneration,
    readerGeneration: pending.readerGeneration, taskId: pending.taskId, root, target, range };
  historyLocation = location;
  retireReadingMeasurement(root);
  const key = root.dataset.key;
  acceptReading(key, root, browser('reading', { state: readingState(key, root), event: 'locate',
    index: pending.message_index }), location);
  if (root.hasAttribute('data-reading-initial')) layoutReading();
  else revealHistoryLocation(location);
}
function revealHistoryLocation(location) {
  const { root, target, range, readerGeneration } = location;
  root.focus({ preventScroll: true });
  if (range && CSS.highlights && typeof Highlight === 'function') CSS.highlights.set(historyHighlight, new Highlight(range));
  else target.dataset.historyMatch = readerGeneration;
  location.timer = setTimeout(() => clearHistoryHighlight(location), historyHighlightMs);
  timers.add(location.timer);
}
function retryHistoryLocation() {
  currentHistoryLocation();
  const pending = pendingHistoryLocation;
  if (!pending) return;
  if (!sameHistoryVisit(pending)) { retireHistoryLocation(); return; }
  if (!admitted(renderer.generation)) return;
  const target = renderer.target(pending.key);
  const root = target?.closest('[data-reading-root]');
  if (!target?.isConnected || target.dataset.readingAnchor !== 'true' || !root?.clientHeight ||
      !historyReaderOwns(root, pending) || renderer.modal && !renderer.modal.contains(root)) return;
  const record = renderer.records.get(pending.markdown_key);
  const markdown = record?.markdown;
  if (!markdown || !target.contains(record.node)) return;
  // The committed article mounts before its individual Markdown parse and
  // decorations finish. An incomplete prefix cannot prove a missing match.
  if (pending.markdown !== markdown) {
    pending.markdown = markdown;
    pending.settled = false;
    pending.scan = null;
    markdown.whenSettled().then(settled => {
      if (!settled || pendingHistoryLocation !== pending || pending.markdown !== markdown) return;
      pending.settled = true;
      retryHistoryLocation();
    }).catch(fatal);
  }
  if (!pending.settled || pending.frame != null) return;
  pending.scan ??= findHistoryRange(record.node, pending.query);
  const deadline = performance.now() + 4;
  do {
    const result = pending.scan.next();
    if (result.done) { locateHistoryRange(pending, root, target, result.value); return; }
  } while (performance.now() < deadline);
  pending.frame = scheduleDisplay(() => { pending.frame = null; retryHistoryLocation(); });
}
function readingStep(key, node, event) {
  const state = readingState(key, node);
  const dock = node.closest('[data-view]')?.querySelector('[data-composer-dock]');
  const decision = browser('reading', { state, event,
    dock_height: String(dock?.getBoundingClientRect().height ?? 0),
    viewport_height: String(node.clientHeight), reduced_motion: matchMedia('(prefers-reduced-motion: reduce)').matches });
  acceptReading(key, node, decision);
}
function scheduleReadingLayout() {
  if (readingLayoutScheduled || disposed) return;
  readingLayoutScheduled = true;
  // Restore after this batch of DOM writes, before an intermediate scroll
  // position reaches the next paint. Physical layout may update again later.
  queueMicrotask(() => {
    readingLayoutScheduled = false;
    if (!disposed) { retryHistoryLocation(); layoutReading(); }
  });
}
const unsettledReadingContent = '[data-markdown-parsing], .code-block[data-interactive-preview-candidate]:not([data-interactive-active], [data-interactive-preview-failed])';
function layoutReading() {
  for (const node of surface.querySelectorAll('[data-reading-root="true"]')) {
    const locating = pendingHistoryLocation && historyReaderOwns(node, pendingHistoryLocation);
    const generation = node.dataset.readerGeneration;
    const completing = node.hasAttribute('data-reading-initial');
    if (readingVisits.get(node) !== generation) {
      const loading = node.dataset.readingCommitted === 'true' && (locating || node.querySelector(unsettledReadingContent));
      node.toggleAttribute('data-reading-initial', Boolean(loading));
      // Keep the text measurable for history search while the reader is hidden.
      node.inert = Boolean(loading);
      if (loading) continue;
      // The same viewport that receives the first visible frame must receive
      // its reading position before paint. Later live updates stay visible.
      readingVisits.set(node, generation);
      readingLayouts.delete(node);
    }
    if (locating) continue;
    const dock = node.closest('[data-view]')?.querySelector('[data-composer-dock]');
    const bookmark = readings.get(readingKey(node))?.anchor;
    const anchor = bookmark ? readingAnchor(node, bookmark.key) : null;
    const block = readingBlocks.get(node);
    const bookmarkNode = block?.anchor === anchor && anchor?.contains(block.node) ? block.node : anchor;
    const location = currentHistoryLocation(node);
    const hit = location?.range && firstRangeRect(location.range);
    const signature = JSON.stringify([node.dataset.readerGeneration, node.clientWidth, node.clientHeight,
      node.scrollHeight, dock?.getBoundingClientRect().height ?? 0,
      bookmarkNode ? bookmarkNode.getBoundingClientRect().top - readingTop(node) + node.scrollTop : null,
      hit ? hit.top - readingTop(node) + node.scrollTop : null]);
    if (readingLayouts.get(node) === signature && node.style.getPropertyValue('scroll-padding-block-end') !== '') continue;
    readingLayouts.set(node, signature);
    readingStep(node.dataset.key, node, 'layout');
    if (completing && location) revealHistoryLocation(location);
  }
}
function dismiss(event) {
  // DEFENSE: An inner menu can consume Escape before it reaches the enclosing dialog.
  if (event.defaultPrevented) return;
  // DEFENSE: Escape from an open select picker bubbles before the browser closes it.
  if (event.type === 'keydown' && event.key === 'Escape' && CSS.supports('selector(select:open)') &&
      event.target.closest?.('select:open')) return;
  const modal = renderer.modalRecord();
  const dismissal = modal?.events.find(binding => binding.kind === 'dismiss');
  const behavior = modal?.metadata.layer;
  if (!dismissal || !admitted(modal.generation)) return;
  if (event.type === 'keydown' && event.key === 'Escape' && behavior.escape || event.type === 'pointerdown' && behavior.outside && (!modal.node.contains(event.target) || event.target === modal.node && (() => {
    const box = modal.node.getBoundingClientRect();
    return event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom;
  })())) {
    event.preventDefault();
    dispatch({ ...renderer.input(modal, dismissal.action), value: event.type === 'keydown' ? 'escape' : 'outside' });
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
  browserId: randomBrowserIdentifier(), limits: boundary('audio.contract', {}),
});
const chatgptLogin = new ChatGPTLogin({
  request, emit: dispatch,
  loginTarget(method, url) {
    const parsed = new URL(url);
    const operation = method === 'device_code' ? 'audio.device_login_target' : 'audio.login_target';
    return boundary(operation, { url: parsed.href, protocol: parsed.protocol,
      hostname: parsed.hostname, port: parsed.port, pathname: parsed.pathname,
      username: parsed.username, password: parsed.password, search: parsed.search, hash: parsed.hash }).url;
  },
  selectCode(key) {
    const node = renderer.resolveTarget(key);
    const selection = document.getSelection();
    // DEFENSE: The dialog can be dismissed or its document replaced while clipboard permission is pending.
    if (!node || !selection) return;
    const range = document.createRange();
    range.selectNodeContents(node);
    selection.removeAllRanges();
    selection.addRange(range);
  },
});

async function authenticate(effect) {
  connection?.abort();
  const controller = new AbortController();
  connection = controller;
  let ready = false;
  let streamNotices = [];
  try {
    // A journal namespace change ends the old subscription; the authenticated
    // connection observes a fresh snapshot and binds the new namespace.
    while (!disposed && connection === controller && !controller.signal.aborted) await observeConnection({
      request: (url, signal) => request(url, { signal: AbortSignal.any([signal, readDeadline()]) }),
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
      notice(value) {
        if (value.type === 'selvedge-update') {
          showUpdateStatus(value);
          return false;
        }
        streamNotices.push(value);
        return true;
      },
      async publish() {
        const notices = streamNotices;
        streamNotices = [];
        const namespace = publication.namespace;
        let started = performance.now();
        for (const value of notices) {
          if (performance.now() - started >= 8) {
            await new Promise(resolve => setTimeout(resolve, 0));
            started = performance.now();
          }
          if (disposed || connection !== controller || controller.signal.aborted ||
              publication.namespace !== namespace) return;
          dispatch({ type: 'stream', value });
        }
      },
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
surface.addEventListener('scroll', event => {
  if (event.target === boardTrack) updateBoardScroll();
}, true);
surface.addEventListener('click', event => {
  const button = event.target.closest?.('[data-board-scroll]');
  if (!boardTrack || !button || button.getAttribute('aria-disabled') === 'true') return;
  scrollBoard(button.dataset.boardScroll === 'next' ? 1 : -1);
});
surface.addEventListener('keydown', event => {
  // DEFENSE: WebKit does not scroll the focused board region on arrow keys.
  if (!event.defaultPrevented && !event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey &&
      (event.key === 'ArrowLeft' || event.key === 'ArrowRight') &&
      event.target === boardTrack && boardTrack.scrollWidth > boardTrack.clientWidth) {
    event.preventDefault();
    scrollBoard(event.key === 'ArrowRight' ? 1 : -1);
  }
  if (event.key !== 'Escape') return;
  for (const node of surface.querySelectorAll('[data-help]:hover,[data-help]:focus-visible')) node.setAttribute('data-help-dismissed', '');
});
for (const name of ['pointerout', 'focusout']) surface.addEventListener(name, event => {
  const node = event.target.closest?.('[data-help-dismissed]');
  if (node && !node.contains(event.relatedTarget)) node.removeAttribute('data-help-dismissed');
});
surface.addEventListener('pointerover', event => {
  const label = event.target.closest?.('[data-overflow-label]');
  if (label && label.scrollWidth > label.clientWidth) label.title = label.dataset.overflowLabel;
});
surface.addEventListener('pointerout', event => {
  const label = event.target.closest?.('[data-overflow-label]');
  if (label && !label.contains(event.relatedTarget)) label.removeAttribute('title');
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
  if (placement) {
    event.preventDefault();
    dispatch({ ...placement.action, generation: source.generation, value: placement.target });
  }
});
surface.addEventListener('dragend', () => { draggedCard = null; });

async function completeCommand(effect) {
  const namespace = publication.namespace;
  try {
    const value = await requestCommand(effect.command, effect.read_only ? readDeadline() : undefined);
    if (publication.namespace === namespace && value !== undefined)
      dispatch({ type: 'completed', ticket: effect.ticket, ok: true, value });
  } catch (error) {
    // DEFENSE: A lost reply ends a read observation. The server may have
    // committed a mutation, so preserve its ticket and duplicate protection.
    if (publication.namespace === namespace) {
      dispatch(effect.read_only
        ? { type: 'completed', ticket: effect.ticket, ok: false, error: error.message }
        : { type: 'completion_failed', ticket: effect.ticket, error: error.message, body: error.body ?? null });
    }
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
function assessCommand(effect) {
  const namespace = publication.namespace;
  const key = ticketKey(effect.request.editor);
  assessments.get(key)?.abort();
  const controller = new AbortController();
  assessments.set(key, controller);
  const job = { effect, namespace, key, controller };
  if (effect.request.editor.kind !== 'candidate') return performAssessment(job);
  candidateAssessments.set(key, job);
  if (!drainingCandidates) return assessCandidates();
}
async function assessCandidates() {
  drainingCandidates = true;
  try {
    // The service already serializes these checks. Keep only one candidate
    // request in flight so the browser can fetch a state snapshot for its SSE
    // subscription while the chooser evaluates the rest of the catalog.
    while (!disposed && candidateAssessments.size) {
      await new Promise(resolve => setTimeout(resolve, 0));
      const next = candidateAssessments.entries().next();
      if (disposed || next.done) return;
      const [key, job] = next.value;
      candidateAssessments.delete(key);
      // A queued check belongs to the snapshot against which it was issued.
      if (!sameGeneration(job.effect.request.sequence, publication.sequence)) {
        if (assessments.get(key) === job.controller) assessments.delete(key);
        continue;
      }
      await performAssessment(job);
    }
  } finally { drainingCandidates = false; }
}
async function performAssessment({ effect, namespace, key, controller }) {
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
function configurationReply(reply) {
  // DEFENSE: A configuration conflict or domain refusal can arrive as a structured result.
  if (reply?.ok !== true) throw new Error(reply?.error?.message ?? 'Configuration request failed');
  return reply.result;
}
async function copyText(text) {
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {
      // DEFENSE: Browser clipboard permissions can reject a direct write after a button click.
    }
  }
  // DEFENSE: The async Clipboard API is absent on the VPN's HTTP origin.
  const active = document.activeElement;
  const field = document.createElement('textarea');
  field.value = text;
  field.readOnly = true;
  field.style.cssText = 'position:fixed;inset:0;inline-size:1px;block-size:1px;opacity:0;pointer-events:none';
  (active?.closest('dialog:modal') ?? document.body).append(field);
  try {
    field.focus({ preventScroll: true });
    field.select();
    if (!document.execCommand('copy')) throw new Error('Clipboard write rejected');
  } finally {
    field.remove();
    active?.focus({ preventScroll: true });
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
    case 'read_service_configuration':
      return settled('service_configuration_loaded', effect.ticket, async () =>
        configurationReply(await request('/api/service-configuration')));
    case 'write_service_configuration':
      return settled('service_configuration_written', effect.ticket, async () =>
        configurationReply(await post('/api/service-configuration', effect.body)));
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
    case 'cloud_repository': return settled('cloud_repository_completed', effect.ticket, async () => {
      const body = await post('/api/browser/observation', { kind: 'cloud-repository', primary: effect.primary });
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
      if (node) { retireHistoryLocation(node); readingStep(node.dataset.key, node, 'follow'); }
      return;
    }
    case 'scroll_to_message': {
      retireHistoryLocation();
      pendingHistoryLocation = { ...effect, namespace: publication.namespace,
        navigationGeneration: integral(state.navigation.generation), readerGeneration: integral(effect.reader_generation).toString(),
        taskId: integral(effect.task_id).toString() };
      retryHistoryLocation();
      return;
    }
    case 'selection_bytes': applyByteSelection(renderer.resolveTarget(effect.key), integral(effect.start), integral(effect.end)); return;
    case 'clipboard': {
      try {
        await copyText(effect.text);
        if (current()) {
          announcements.setAttribute('role', 'status');
          announcements.setAttribute('aria-live', 'polite');
          announcements.classList.add('visually-hidden');
          announcements.textContent = '已复制';
        }
      } catch {
        // DEFENSE: The browser can deny both clipboard mechanisms. The path stays visible for manual copying.
        emit({ type: 'native_failed', error: '复制失败，请选中文本后复制。' });
      }
      return;
    }
    case 'audio_login': return chatgptLogin.start(integral(effect.ticket), effect.method);
    case 'release_audio_login': return chatgptLogin.release(integral(effect.ticket));
    case 'copy_audio_login_code': return chatgptLogin.copy(integral(effect.ticket), effect.key, effect.code);
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
  const record = renderer.records.get(node.dataset.key);
  if (record?.node !== node) return;
  const binding = record?.events.find(binding => binding.kind === 'value' && binding.action.op === 'element');
  if (!binding || !record.metadata.selection_enabled || !admitted(record.generation)) return;
  const selection = observedSelection(node, renderer.composing.has(node));
  const observed = stringifyJson(selection);
  if (selections.get(node) === observed) return;
  selections.set(node, observed);
  dispatch({ ...renderer.input(record, binding.action), gesture: 'selection', value: selection });
}
document.addEventListener('selectionchange', selectionChanged);

window.addEventListener('pagehide', () => {
  disposed = true; document.removeEventListener('selectionchange', selectionChanged); document.removeEventListener('keydown', dismiss); document.removeEventListener('pointerdown', dismiss); connection?.abort(); chatgptLogin.dispose(); audio.dispose(); motion.dispose(); editorRepair.dispose(); physical.dispose(); renderer.dispose(); storage.flush();
  clearInterval(clockRefresh); document.removeEventListener('visibilitychange', refreshClock);
  boardTrackResize.disconnect();
  for (const timer of timers) clearTimeout(timer);
  for (const entry of codeBlocks.values()) for (const physical of entry.views.values()) physical.renderer?.dispose();
  for (const controller of transfers.values()) controller.abort();
  for (const controller of assessments.values()) controller.abort();
  candidateAssessments.clear();
  for (const node of readingMeasurements.keys()) retireReadingMeasurement(node);
  retireHistoryLocation();
  window.removeEventListener('pointerup', endReadingPointer, true);
  window.removeEventListener('pointercancel', endReadingPointer, true);
  for (const resource of resources) URL.revokeObjectURL(resource);
  if (layoutFrame !== null) cancelAnimationFrame(layoutFrame);
  if (measurementFrame !== null) cancelAnimationFrame(measurementFrame);
  if (measurementTask !== null) clearTimeout(measurementTask);
}, { once: true });
window.addEventListener('focus', () => chatgptLogin.focus());
for (const preference of ['(prefers-color-scheme: dark)', '(prefers-reduced-motion: reduce)'])
  matchMedia(preference).addEventListener('change', schedulePhysicalRefresh);
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
