import { boundary } from './model-boundary.mjs';
import { browser, interaction, presentNative, presentBrowserDocument } from './browser-model-boundary.mjs';
import { JsonNumber, parseJson, stringifyJson } from './json-tokens.mjs';
import { Presentation, appendPhysicalChild, filesFromEvent } from './native-dom.mjs';
import { editorKeyboard, applyByteSelection, selectingRadioGroup, radioTabTargets } from './keyboard.mjs';
import { observeConnection } from './connection.mjs';
import { applyProgramUpdates, browserHistoryTasksHeader, browserOutlineHeader, browserSequenceHeader,
  indexProgramTasks, installBrowserHistory, programTask, replaceProgramTask, retainBrowserHistory } from './program-updates.mjs';
import { AudioRuntime } from './audio.mjs';
import { ChatGPTLogin } from './chatgpt-login.mjs';
import { InteractiveSnapshotStorage } from './interactive-storage.mjs';
import { createEditorRepairPlacement, createLayoutRevealer, revealAndFocus, revealInScrollport } from './layout-reveal.mjs';
import { PresentationMotion } from './presentation-motion.mjs';
import { ToolActivity } from './tool-activity.mjs';
import { safeHref, scheduleDisplay, cancelDisplay } from './markdown.mjs';
import { findHistoryRange, firstRangeRect } from './history-location.mjs';
import { createPhysicalMeasurer } from './physical-measurement.mjs';
import { installModelPickerPreview } from './model-picker.mjs';
import { installWorkflowViewport, showWorkflowTimes } from './workflow-viewport.mjs';
import { observeSingleLineLabels } from './single-line-labels.mjs';

const surface = document.getElementById('surface');
const disposeSingleLineLabels = observeSingleLineLabels(surface);
installModelPickerPreview(surface);
const synchronizeWorkflowViewport = installWorkflowViewport(surface);
const notices = document.getElementById('browser-notices');
const announcements = document.getElementById('announcements');
const updateStatus = document.getElementById('selvedge-update-status');
const documentRelease = document.querySelector('meta[name="selvedge-release"]')?.content;
const updateSessionKey = 'selvedge-update-session';
const files = new Map();
const transfers = new Map();
const workflowReceipts = new Map();
const browserCommandReplies = new Map();
const awaitingCommandSnapshots = new Set();
const assessments = new Map();
const pendingAssessments = new Map();
const historyReads = new Map();
let visibleHistoryTasks = [];
let drainingAssessments = false;
const resources = new Set();
const timers = new Set();
const readings = new Map();
const readingMeasurements = new Map();
const readingPointers = new Map();
const readingLayouts = new WeakMap();
const readingVisits = new WeakMap();
const readingBlocks = new WeakMap();
const visibleReadingAnchors = new WeakMap();
const restoredReadingOffsets = new WeakMap();
const alignedReadingOffsets = new WeakMap();
let observedReadingGeometry = new Set();
const readingResize = new ResizeObserver(() => {
  // Reader reflow and disclosure transitions can change the layout
  // independently of document publication.
  if (!disposed) layoutReading();
});
const selections = new WeakMap();
const codeBlocks = new Map();
const storagePolicy = interaction('interactive_storage_policy');
const storage = new InteractiveSnapshotStorage({ ...storagePolicy,
  maximumDocuments: Number(storagePolicy.maximumDocuments instanceof JsonNumber ? storagePolicy.maximumDocuments.source : storagePolicy.maximumDocuments),
  maximumBytes: Number(storagePolicy.maximumBytes instanceof JsonNumber ? storagePolicy.maximumBytes.source : storagePolicy.maximumBytes) });
const activeModal = () => renderer.modal;
const historyResultsSelector = 'main > [data-page-region="history-results"]';
const reveal = createLayoutRevealer(surface, activeModal);
const editorRepair = createEditorRepairPlacement(activeModal);
const motion = new PresentationMotion(surface, activeModal);
const toolActivity = new ToolActivity(surface);
let state = interaction('initial');
let world = null;
let publication = { generation: 0, phase: 'awaiting', namespace: '', sequence: 0,
  displayed_generation: null, native_displayed_generation: null };
let environment = null;
let measuring = null;
let measureAgain = false;
let measurementFrame = null;
let measurementTask = null;
let connection = null;
let browserStateRead = null;
let disposed = false;
let clockRefresh = null;
let sourceFresh = false;
let layoutFrame = null;
let readingLayoutFrame = null;
let revealingReader = false;
let pendingHistoryLocation = null;
let historyLocation = null;
let searchResultsPosition = null;
let historyResultsNode = null;
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

let releaseCheckpointSaved = false;
function saveTabSession() {
  if (!publication.namespace || world === null) return;
  const session = interaction('update_session', { state, world, environment });
  sessionStorage.setItem(updateSessionKey, stringifyJson({ namespace: publication.namespace, session }));
}
function reloadForRelease(release) {
  if (!documentRelease || !release || release === documentRelease) return false;
  try {
    saveTabSession();
    releaseCheckpointSaved = true;
  } catch (error) {
    // DEFENSE: Browser settings or storage quota can prevent saving this tab's drafts.
    updateStorageProblem = `无法保存更新前的草稿，当前页面保持打开：${error.message}`;
    showUpdateStatus({ status: 'idle' });
    return false;
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
      state = interaction('restore_update_session', { state, world, environment, checkpoint: session });
    }
    sessionStorage.removeItem(updateSessionKey);
  } catch (error) {
    // DEFENSE: Browser storage can be disabled or its checkpoint can be unreadable.
    updateStorageProblem = `无法恢复此标签页的草稿：${error.message}`;
    showUpdateStatus({ status: 'idle' });
  }
}

function taskObservation(effect, fields) {
  return effect.task_id === undefined ? fields : { ...fields, task_id: effect.task_id };
}

const requestScope = () => ({ namespace: publication.namespace, ticket: state.services.connection.ticket });
const ownsRequestFailure = scope => publicationEvent('request_failure', { expected_namespace: scope.namespace,
  ticket: scope.ticket, connection: state.services.connection });
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
const post = (url, value, signal, headers) => request(url, { method: 'POST', signal,
  headers: { 'content-type': 'application/json', ...headers }, body: stringifyJson(value) });
const browserHeaders = (initial = false) => ({
  [browserOutlineHeader]: 'true',
  [browserHistoryTasksHeader]: visibleHistoryTasks.join(','),
  ...(!initial && world !== null ? { [browserSequenceHeader]: String(integral(publication.sequence)) } : {}),
});

function readBrowserState(signal, initial = false) {
  const read = () => request('/api/browser/state', { headers: browserHeaders(initial),
    signal: AbortSignal.any([signal, readDeadline()]) });
  if (initial) return read();
  if (browserStateRead?.signal === signal) return browserStateRead.result;
  const result = read().finally(() => {
    if (browserStateRead?.result === result) browserStateRead = null;
  });
  browserStateRead = { signal, result };
  return result;
}

function settleCommandSnapshots(replaced = false) {
  for (const pending of awaitingCommandSnapshots) {
    if (!replaced && integral(publication.sequence) < pending.sequence) continue;
    awaitingCommandSnapshots.delete(pending);
    pending.resolve(!replaced);
  }
}

async function refreshCommandSnapshot(pending, namespace, controller) {
  const scope = requestScope();
  const current = () => !disposed && connection === controller && !controller.signal.aborted &&
    publication.namespace === namespace && awaitingCommandSnapshots.has(pending);
  try {
    // A shared read may have started before this command committed. In that
    // case read once more from the newly installed cursor.
    for (let reads = 0; current() && reads < 2; reads++) {
      const body = await readBrowserState(controller.signal);
      if (current() && body !== null) snapshot(body, namespace);
    }
    if (current()) throw new Error('The service snapshot did not reach the confirmed command.');
  } catch (error) {
    // DEFENSE: A read can fail after the write was confirmed. Recover the
    // observation through the connection; keep the result and its ticket.
    if (current() && ownsRequestFailure(scope)) {
      controller.abort();
      dispatch({ type: 'disconnected', ticket: scope.ticket, error: error.message, revoked: authorizationRevoked(error) });
    }
  }
}

async function requestCommand(command, signal, returnsCommit = false, received) {
  const expected = publication.namespace;
  const requestId = returnsCommit ? randomBrowserIdentifier() : null;
  const receipt = returnsCommit ? Promise.withResolvers() : null;
  if (receipt) browserCommandReplies.set(requestId, receipt.promise);
  let body;
  try {
    try {
      const headers = { ...browserHeaders(), ...(receipt ? { 'x-selvedge-browser-request-id': requestId } : {}) };
      body = await post('/api/browser/command', { command }, signal, headers);
    } catch (error) {
      // DEFENSE: An authoritative rejection uses a non-2xx HTTP status.
      if (error.body && (error.body.snapshot_required === true || Object.hasOwn(error.body, 'updates'))
          && Object.hasOwn(error.body, 'reply')) body = error.body;
      else throw error;
    }
    if (!publicationEvent('completion', { expected_namespace: expected, incoming_namespace: body.namespace })) return;
    if (body.snapshot_required !== true) {
      snapshot(body, expected);
      return body.reply;
    }
  } finally {
    if (receipt) {
      browserCommandReplies.delete(requestId);
      receipt.resolve();
    }
  }
  const sequence = integral(body.sequence);
  if (sequence <= integral(publication.sequence)) return body.reply;
  received?.(body.reply);
  const { promise, resolve } = Promise.withResolvers();
  const pending = { sequence, resolve };
  awaitingCommandSnapshots.add(pending);
  if (connection) void refreshCommandSnapshot(pending, expected, connection);
  if (await promise) return body.reply;
}

function publicationEvent(event, values = {}) {
  return browser('publication', { ...publication, event, ...values });
}
function admitted(generation) {
  return generation !== null && generation !== undefined &&
    publicationEvent('native_admit', { receipt_generation: generation });
}
function acceptsElement(input) {
  return interaction('accepts_element', { state, input, world, environment, generation: publication.generation,
    namespace: publication.namespace, displayed_generation: publication.displayed_generation,
    native_displayed_generation: publication.native_displayed_generation, now: BigInt(Math.floor(Date.now() / 1000)) });
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
  const newNamespace = body.namespace !== publication.namespace;
  if (newNamespace) retireDocumentViews();
  if (body.updates === undefined)
    world = firstSnapshot || newNamespace ? indexProgramTasks(body.program) : retainBrowserHistory(body.program, world);
  else world = applyProgramUpdates(world, body.updates.slice(Number(integral(publication.sequence) - integral(body.after))));
  publication = publicationEvent('observe', { observed_namespace: body.namespace, observed_sequence: body.sequence });
  if (firstSnapshot) restoreUpdateSession();
  dispatch({ type: 'snapshot' });
  settleCommandSnapshots();
  // A committed launch can arrive through the live snapshot before its HTTP
  // reply, or after that connection was interrupted.
  if (workflowReceipts.size) {
    for (const instance of world.workflow_instances) {
      const receipt = instance.browser_launch_receipt;
      const pending = workflowReceipts.get(receipt?.key);
      if (pending?.namespace !== publication.namespace) continue;
      workflowReceipts.delete(receipt.key);
      dispatch({ type: 'completed', ticket: pending.ticket, ok: true, value: receipt.reply });
    }
  }
  return true;
}

function historyLoaded(task) {
  return task !== undefined && task.history_pending !== true;
}
function synchronizeConversationHistory(visible) {
  visibleHistoryTasks = visible.map(id => Number(integral(id)));
  const selected = new Set(visibleHistoryTasks);
  for (const [id, controller] of historyReads) {
    if (selected.has(id)) continue;
    historyReads.delete(id);
    controller.abort();
  }
  if (world === null) return;
  for (const id of selected) {
    const current = programTask(world.tasks, id);
    if (current === undefined || historyLoaded(current) || historyReads.has(id)) continue;
    const controller = new AbortController();
    historyReads.set(id, controller);
    const namespace = publication.namespace;
    const owns = () => !disposed && historyReads.get(id) === controller && namespace === publication.namespace;
    void (async () => {
      while (owns() && !historyLoaded(programTask(world.tasks, id))) {
        const requested = programTask(world.tasks, id);
        const prefix = requested.history ?? [];
        const after = prefix.length;
        const expected = Number(integral(requested.cursor));
        const body = await request(`/api/browser/state?history=${id}&after=${after}`, {
          signal: AbortSignal.any([controller.signal, readDeadline()]),
        });
        if (!owns() || historyLoaded(programTask(world.tasks, id))) return;
        // DEFENSE: A reply may belong to a replaced journal or a broken history source.
        if (body?.namespace !== namespace || integral(body.task_id) !== BigInt(id) || body.after !== after ||
            !Array.isArray(body.history) || body.history.length < expected - after || !Array.isArray(body.tools))
          throw new Error('The conversation history does not match its committed cursor');
        const task = programTask(world.tasks, id);
        const cursor = Number(integral(task.cursor));
        const received = prefix.concat(body.history.slice(0, cursor - after));
        const history = (task.history?.length ?? 0) > received.length ? task.history : received;
        world = replaceProgramTask(world, id, installBrowserHistory({ ...task, tools: body.tools }, history));
        if (history.length === cursor) dispatch({ type: 'snapshot' });
        // If a later commit arrived during the read, request only the
        // remaining suffix and keep the incomplete timeline hidden.
      }
    })().catch(error => {
      if (owns() && !authorizationRevoked(error)) fatal(error);
    }).finally(() => {
      if (historyReads.get(id) === controller) historyReads.delete(id);
    });
  }
}

function cancelConversationHistoryReads() {
  for (const controller of historyReads.values()) controller.abort();
  historyReads.clear();
}
function retireDocumentViews() {
  cancelConversationHistoryReads();
  for (const entry of codeBlocks.values()) for (const physical of entry.views.values()) physical.renderer?.dispose();
  codeBlocks.clear(); readings.clear(); files.clear(); renderer.reset();
  for (const node of readingMeasurements.keys()) retireReadingMeasurement(node);
  retireHistoryLocation(); pendingFocus = null; suspendedFocus = null; focusRequest++;
  searchResultsPosition = null;
  historyResultsNode = null;
  suspendedPrefixFocus = null;
  for (const controller of assessments.values()) controller.abort();
  assessments.clear();
  pendingAssessments.clear();
  workflowReceipts.clear();
  browserCommandReplies.clear();
  settleCommandSnapshots(true);
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
  renderer.reset();
  renderer.renderDocument(ops => presentBrowserDocument('recovery', {
    root_font_size_milli: physical.viewport().root_font_size_milli, generation: publication.generation, reason,
  }, ops), publication.generation);
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
    render(decision.native_stream ? 'stream' : 'region');
  synchronizeConversationHistory(decision.visible_history_tasks);
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
function render(mode = 'region') {
  if (disposed) return;
  const recovery = publicationEvent('recovery');
  if (recovery !== null) { renderRecovery(recovery); return; }
  if (!environment) return;
  try { present(mode); }
  catch (error) {
    // DEFENSE: Native DOM updates can fail during a scene change. Keep the
    // same recovery action available as for a failed physical observation.
    fatal(error);
  }
}
function refreshPageLayout(previous, offset, routeChanged) {
  const track = surface.querySelector('[data-page-region="board-stages"]');
  const firstLane = track?.firstElementChild ?? null;
  const controls = surface.querySelector('[data-board-scroll-controls]');
  if (controls !== boardScrollControls || track !== boardTrack) {
    boardScrollControls = controls;
    for (const control of controls?.querySelectorAll('[data-board-scroll], [data-board-stage-jump]') ?? []) {
      if (track) control.setAttribute('aria-controls', track.id);
      else control.removeAttribute('aria-controls');
    }
  }
  if (track !== boardTrack || firstLane !== boardFirstLane) {
    boardTrackResize.disconnect();
    if (track !== boardTrack) boardHasOverflow = false;
    boardTrack = track;
    boardFirstLane = firstLane;
    if (track) boardTrackResize.observe(track);
    if (firstLane) boardTrackResize.observe(firstLane);
  }
  if (controls) controls.hidden = !(track && boardHasOverflow);
  const current = surface.querySelector(historyResultsSelector);
  historyResultsNode = current;
  if (previous === current && !routeChanged) return;
  if (previous) searchResultsPosition = { key: previous.dataset.key, offset };
  if (routeChanged || previous) {
    const main = surface.querySelector('[data-measure-region="main"] > main');
    main?.scrollTo(0, 0);
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
    if (button.getAttribute('aria-disabled') !== String(!available)) button.setAttribute('aria-disabled', String(!available));
  }
}
function scrollBoard(direction) {
  const edge = boardTrack.getBoundingClientRect().left + boardTrack.clientLeft;
  const lanes = Array.from(boardTrack.children);
  const ordered = direction > 0 ? lanes : lanes.reverse();
  const adjacent = ordered.find(lane => direction * (lane.getBoundingClientRect().left - edge) > 1);
  if (adjacent) boardTrack.scrollBy({ left: adjacent.getBoundingClientRect().left - edge });
  else boardTrack.scrollLeft = direction > 0 ? boardTrack.scrollWidth : 0;
}
function present(mode) {
  surface.dataset.displayPending = String(publicationEvent('pending'));
  const generation = publication.generation;
  const materialize = kind => ops => presentNative(kind, state, world, environment, generation, ops);
  const starting = renderer.document == null;
  if (starting) renderer.renderDocument(materialize('document'), generation);
  const streamed = !starting && mode === 'stream' && renderer.renderStream(materialize('stream'), generation);
  const previousResults = historyResultsNode?.isConnected ? historyResultsNode : null;
  const scrollport = !streamed ? previousResults?.parentElement : null;
  const offset = scrollport?.scrollTop;
  const regions = !streamed && renderer.renderRegions(materialize('region'), generation);
  if (!streamed && !regions) throw new Error('Unable to publish the native regions');
  const pageChanged = starting || regions?.page_changed;
  if (pageChanged) {
    refreshPageLayout(previousResults, offset, regions?.route_changed);
    synchronizeWorkflowViewport();
  }
  const freshness = String(sourceFresh);
  const freshnessChanged = surface.dataset.sourcesFresh !== freshness;
  if (freshnessChanged) surface.dataset.sourcesFresh = freshness;
  const layoutChanged = pageChanged || regions?.focus_scope || regions?.layout_changed;
  if (pageChanged || regions?.layout_changed && !regions.layers_changed) schedulePhysicalRefresh();
  if (pageChanged || regions?.layers_changed || regions?.remove?.length) retireDetachedCodeViews();
  if (pageChanged || regions?.layers_changed) {
    layoutReading(true);
    showWorkflowTimes(surface);
  }
  if (layoutChanged) observeReadingGeometry();
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
      if (layoutChanged && publicationEvent('ready')) {
        renderer.refreshNativeTargets();
        scheduleLayoutReveal();
      }
      if (layoutChanged) scheduleReadingLayout();
      retryFocus();
    };
    if (renderer.isCaughtUp()) publishPrefix(true);
    else {
      synchronizePrefixAuthority();
      renderer.whenCaughtUp().then(publishPrefix).catch(fatal);
    }
  } else synchronizePrefixActions();
  if (layoutChanged) {
    scheduleLayoutReveal();
    editorRepair.refresh();
    retryHistoryLocation();
  }
  if (layoutChanged || freshnessChanged) motion.refresh();
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
function scheduleLayoutReveal() {
  if (layoutFrame !== null || disposed) return;
  layoutFrame = requestAnimationFrame(() => {
    layoutFrame = null;
    reveal();
    renderer.confineAnchoredLayers();
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
  try { await measuring; } finally { measuring = null; }
}
const selectionEncoder = new TextEncoder();
function observedSelection(node, composing = false) {
  const text = node.value;
  const first = node.selectionStart ?? text.length;
  const last = node.selectionEnd ?? text.length;
  const start = selectionEncoder.encode(text.slice(0, first)).length;
  const end = first === last ? start : selectionEncoder.encode(text.slice(0, last)).length;
  return { start, end, direction: node.selectionDirection, composing };
}
function registerFiles(action, selected) {
  for (const file of selected) {
    const handle = randomBrowserIdentifier(); files.set(handle, file);
    dispatch({ ...action, value: { handle, name: file.name, mime: file.type, bytes: file.size } });
  }
}
surface.addEventListener('focusin', () => { focusRequest++; });
const renderer = new Presentation(surface, {
  resolveTarget(source) { return browser('resolve_target', source); },
  fieldSession(source) { return browser('field_session', source); },
  focusPlan(source) { return browser('focus_plan', source); },
  modalChanged(modal) {
    appendPhysicalChild(modal ?? document.body, notices);
    // Native menus can clip their descendants or establish a transformed
    // containing block. Keep the live regions inside the active modal for
    // accessibility and paint their notices in the viewport's top layer.
    if (!modal) notices.removeAttribute('popover');
    else if (notices.showPopover && !notices.matches(':popover-open')) {
      notices.popover = 'manual';
      notices.showPopover();
    }
  },
  keyboard(source) { return browser('key', source); },
  focus(event, key, node) {
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
      renderer.reset();
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
      const selection = observedSelection(node, event.isComposing || renderer.composing.has(node));
      // The input event already supplies the current caret. A later native
      // selectionchange for that same caret adds no observation.
      const decision = dispatch({ ...binding.action, value: node.value, raw: node.value, selection });
      const field = renderer.records.get(key);
      if (decision?.handled && decision.error === null && field?.node === node && field.metadata.selection_enabled)
        selections.set(node, stringifyJson(selection));
      else selections.delete(node);
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
    const composing = !keyboard.editing;
    if (record.metadata.key_input && keyboard.unmodified) {
      const input = { op: 'element', key, gesture: 'key', generation: record.generation, value: { key: event.key } };
      if (acceptsElement(input)) {
        event.preventDefault(); dispatch(input); return;
      }
    }
    const form = node.form;
    if (event.key === 'Enter' && form && (node.tagName === 'TEXTAREA' || node.tagName === 'INPUT')) {
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
    if (node.dataset.readingRoot === 'true' && event.target.closest('[data-reading-root="true"]') === node &&
        !event.target.closest('[data-tool-output]')) {
      const state = readingState(key, node);
      const editable = event.target.matches('input,textarea,select') || event.target.isContentEditable;
      if (!editable && ['ArrowDown', 'PageDown', 'End'].includes(event.key) && atReadingBottom(node))
        reachedReadingBottom(key, node, state);
      else acceptReading(key, node, browser('reading', { state, event: 'key', keyboard: event.key, editable }));
    }
  },
  reading(type, event, key, node, touchDelta) {
    if (node.dataset.readingRoot !== 'true') return;
    if (type === 'scroll'
      ? event.target.closest('[data-reading-root="true"]') !== node || event.target.closest('[data-tool-output]')
      : event.target !== node) return;
    if (type === 'pointer') {
      const rect = node.getBoundingClientRect(), style = getComputedStyle(node);
      const left = rect.left + node.clientLeft;
      const right = left + node.clientWidth;
      const inLeftGutter = event.clientX < left && node.clientLeft > Number.parseFloat(style.borderLeftWidth);
      const inRightGutter = event.clientX >= right && rect.right - right > Number.parseFloat(style.borderRightWidth);
      if (!inLeftGutter && !inRightGutter) return;
    }
    if (type === 'scroll' || type === 'pointer') {
      if (type === 'scroll') {
        const delta = touchDelta ?? event.deltaY;
        if (!delta || event.shiftKey || event.ctrlKey ||
            (event.type === 'wheel' && Math.abs(event.deltaX) > Math.abs(delta))) return;
        for (let child = event.target; child && child !== node; child = child.parentElement) {
          if (child.scrollHeight <= child.clientHeight) continue;
          const style = getComputedStyle(child);
          if (/^(auto|scroll)$/.test(style.overflowY) && (style.overscrollBehaviorY !== 'auto' ||
              (delta > 0 ? child.scrollTop + child.clientHeight < child.scrollHeight - 1 : child.scrollTop > 0))) return;
        }
        if (delta > 0 && atReadingBottom(node)) {
          reachedReadingBottom(key, node, readingState(key, node));
          return;
        }
      }
      const state = readingState(key, node);
      requestReadingAnchor(key, node, type === 'pointer' ? event.pointerId : undefined);
      acceptReading(key, node, browser('reading', { state, event: 'scroll' }));
    } else {
      const aligned = alignedReadingOffsets.get(node);
      alignedReadingOffsets.delete(node);
      // An initial alignment can report its scroll after the reader
      // has already asked to move away from the latest reply.
      if (aligned === node.scrollTop) return;
      const state = readingState(key, node);
      if (state.intent !== 'history') return;
      // DEFENSE: restoring a bookmark emits scroll even when the browser clamps
      // it before asynchronous Markdown mounts. That receipt is not a new user position.
      if (restoredReadingOffsets.get(node) === node.scrollTop) return;
      if (currentHistoryLocation(node)) {
        // Reflow can clamp scrollTop before layout restores the hit. A scroll
        // in the same geometry can come from native focus moving to a control.
        if (readingLayouts.get(node)?.dimensions !== readingDimensions(node)) {
          scheduleReadingLayout();
          return;
        }
        retireHistoryLocation(node);
      }
      if (atReadingBottom(node)) reachedReadingBottom(key, node, state);
      else requestReadingAnchor(key, node);
    }
  },
  menuGeometry(bounds) {
    return browser('menu_viewport_correction', Object.fromEntries(
      ['left', 'top', 'width', 'height'].map(name => [name, new JsonNumber(String(bounds[name]))])));
  },
  layout() {
    scheduleReadingLayout();
    if (surface.querySelector('[data-reading-initial]')) revealNewReaders();
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
  scheduleLayoutReveal();
} });

function retireDetachedCodeViews() {
  for (const [key, entry] of codeBlocks) {
    for (const [id, view] of entry.views) {
      if (!view.renderer || view.renderer.root.isConnected) continue;
      view.renderer.dispose();
      entry.views.delete(id);
    }
    if (entry.views.size === 0 && !entry.state.wrap && entry.state.copy.type === 'idle') codeBlocks.delete(key);
  }
}
function publishCode(identity, view, text) {
  const key = browser('code_key', { identity });
  let entry = codeBlocks.get(key);
  const viewKey = stringifyJson(view);
  if (!entry) {
    const decision = browser('code_initial', { identity, text });
    entry = { key, identity, state: decision.state, views: new Map() };
    codeBlocks.set(key, entry);
  }
  const previous = entry.views.get(viewKey);
  const toolbar = renderer.target(browser('code_targets', { identity, view }).toolbar);
  if (!previous || previous.renderer?.root !== toolbar)
    entry.views.set(viewKey, { view, renderer: previous?.renderer ?? null });
  const decision = browser('code_step', { state: entry.state, input: { type: 'source', text } });
  // Source text feeds Copy, while only its copy status and wrapping affect
  // the visible toolbar. Mount a new occurrence or update changed chrome.
  if (!previous || previous.renderer?.root !== toolbar ||
      entry.state.copy.type !== decision.state.copy.type) renderCode(entry, decision);
  else entry.state = decision.state;
}
function renderCode(entry, decision) {
  entry.state = decision.state;
  for (const physical of entry.views.values()) {
    const targets = browser('code_targets', { identity: entry.identity, view: physical.view });
    const target = renderer.target(targets.toolbar);
    if (target) {
      if (!physical.renderer || physical.renderer.root !== target) {
        physical.renderer?.dispose();
        physical.renderer = new Presentation(target, { event(binding, event) {
          if (!prefixAdmitted(renderer.generation)) return;
          event.preventDefault(); codeStep(entry, binding.action.input);
        } }, { isolated: true });
      }
      const metadata = physical.renderer.renderDocument(ops => presentBrowserDocument('code_present', {
        state: entry.state, view: physical.view, environment,
      }, ops));
      const code = renderer.target(targets.body);
      if (code) for (const { name, value } of metadata.body_styles) code.style.setProperty(name, value);
    }
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
  renderCode(entry, browser('code_step', { state: entry.state, input }));
}

const readingKey = node => node.dataset.taskId;
const readingTop = node => node.getBoundingClientRect().top + node.clientTop;
const atReadingBottom = node => node.scrollHeight - node.clientHeight - node.scrollTop <= 1;
const readingDimensions = node => `${node.clientWidth},${node.clientHeight},${node.scrollHeight}`;
function reachedReadingBottom(key, node, state) {
  if (state.intent !== 'history') return;
  retireHistoryLocation(node);
  acceptReading(key, node, browser('reading', { state, event: 'reached_latest' }));
}
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
      if (previous === 'follow') node.scrollTo({ top: node.scrollTop, left: node.scrollLeft, behavior: 'instant' });
    }
    else if (effect.type === 'align_latest') {
      const previous = node.scrollTop;
      node.scrollTo({ top: node.scrollHeight, behavior: effect.animate ? 'smooth' : 'instant' });
      if (!effect.animate && node.scrollTop !== previous) alignedReadingOffsets.set(node, node.scrollTop);
    }
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
  const retained = visibleReadingAnchors.get(node);
  const retainedBox = retained && node.contains(retained) && retained.getBoundingClientRect();
  const spansTop = bounds => bounds && bounds.top <= top && bounds.bottom > top;
  let topElement;
  const firstVisible = (root, selector) => {
    // Jump straight to the painted passage after a scrollbar jump. Retain
    // document order if several matching elements enclose the same point.
    if (topElement === undefined) {
      const box = node.getBoundingClientRect();
      topElement = document.elementFromPoint(box.left + node.clientLeft + node.clientWidth / 2, top);
    }
    let hit = topElement?.closest(selector);
    if (hit && root.contains(hit) && hit !== root) {
      for (let outer = hit.parentElement?.closest(selector); outer && root.contains(outer) && outer !== root;
           outer = outer.parentElement?.closest(selector)) hit = outer;
      if (spansTop(hit.getBoundingClientRect())) return hit;
    }
    // Gaps between articles and overlays can cover the sampling point.
    for (const target of root.querySelectorAll(selector)) {
      const bounds = target.getBoundingClientRect();
      if (bounds.bottom > top && bounds.top < top + node.clientHeight) return target;
    }
    return null;
  };
  const anchor = selected ?? (spansTop(retainedBox) ? retained : firstVisible(node, '[data-reading-anchor]'));
  if (!anchor) return;
  if (!selected) visibleReadingAnchors.set(node, anchor);
  let block = null;
  if (!selected) {
    const lastBlock = readingBlocks.get(node)?.node;
    const selector = '.physical-markdown > .markdown > [data-stable]:not([data-interactive-preview-candidate]:not([data-interactive-active], [data-interactive-preview-failed]))';
    block = lastBlock?.matches(selector) && anchor.contains(lastBlock) && spansTop(lastBlock.getBoundingClientRect())
      ? lastBlock : firstVisible(anchor, selector);
  }
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
  if (!pending) return;
  pending.pointers.delete(event.pointerId);
  if (!pending.pointers.size && atReadingBottom(node))
    reachedReadingBottom(pending.key, node, readingState(pending.key, node));
  else requestReadingAnchor(pending.key, node);
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
    readerGeneration: pending.readerGeneration, taskId: pending.taskId, root, target, range,
    invokingFocus: pending.invokingFocus };
  historyLocation = location;
  retireReadingMeasurement(root);
  const key = root.dataset.key;
  acceptReading(key, root, browser('reading', { state: readingState(key, root), event: 'locate',
    index: pending.message_index }), location);
  if (root.hasAttribute('data-reading-initial')) layoutReading();
  else revealHistoryLocation(location);
}
function revealHistoryLocation(location) {
  const { target, range, readerGeneration } = location;
  const active = document.activeElement;
  if (active === document.body || active === location.invokingFocus || active === location.root) {
    target.setAttribute('tabindex', '-1');
    target.addEventListener('blur', () => target.removeAttribute('tabindex'), { once: true });
    target.focus({ preventScroll: true });
  }
  if (range && CSS.highlights && typeof Highlight === 'function') {
    CSS.highlights.set(historyHighlight, new Highlight(range));
  } else target.dataset.historyMatch = readerGeneration;
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
  // A search hit can belong to an answer that is still streaming. Search
  // the published prefix even if the answer never receives a terminal event.
  if (pending.markdown !== markdown) {
    pending.markdown = markdown;
    pending.prefixLength = markdown.text.length;
    pending.phase = 'waiting-for-text';
    pending.scan = null;
    markdown.prioritizeReadingPassage();
    markdown.whenTextReady(pending.prefixLength).then(ready => {
      if (!ready || pendingHistoryLocation !== pending || pending.markdown !== markdown) return;
      pending.phase = 'search-text';
      retryHistoryLocation();
    }).catch(fatal);
  }
  if (pending.phase === 'waiting-for-text' || pending.phase === 'waiting-for-format' || pending.frame != null) return;
  if (!pending.scan) {
    pending.scan = findHistoryRange(record.node, pending.query);
    pending.scanningDuringFormatting = markdown.decorations.size > 0;
  }
  const deadline = performance.now() + 4;
  do {
    const result = pending.scan.next();
    if (result.done) {
      const range = result.value;
      // Highlighting and math can replace text nodes in their own blocks.
      // Ordinary prose elsewhere in the message is already safe to reveal.
      if (pending.scanningDuringFormatting && pending.phase === 'search-text' && (!range ||
          [range.startContainer, range.endContainer].some(node => node.parentElement?.closest('pre, .math-source')))) {
        pending.phase = 'waiting-for-format';
        markdown.whenCaughtUp(pending.prefixLength).then(ready => {
          if (!ready || pendingHistoryLocation !== pending || pending.markdown !== markdown) return;
          pending.phase = 'search-formatted';
          pending.scan = null;
          retryHistoryLocation();
        }).catch(fatal);
      } else locateHistoryRange(pending, root, target, range);
      return;
    }
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
  if (readingLayoutFrame !== null || disposed) return;
  // Markdown batches, native mounts and resize observations can arrive in
  // separate tasks in the same frame. Restore the reading position once.
  readingLayoutFrame = requestAnimationFrame(() => {
    readingLayoutFrame = null;
    if (!disposed) { retryHistoryLocation(); layoutReading(); }
  });
}
function observeReadingGeometry() {
  const mounted = new Set(surface.querySelectorAll('[data-reading-root], [data-reading-root] [data-task-process]'));
  for (const node of observedReadingGeometry) if (!mounted.has(node)) readingResize.unobserve(node);
  for (const node of mounted) if (!observedReadingGeometry.has(node)) readingResize.observe(node);
  observedReadingGeometry = mounted;
}
function revealNewReaders() {
  if (revealingReader) return;
  revealingReader = true;
  // Align the newly mounted reader before exposing its first visible frame.
  // Continuing Markdown takes the coalesced path once the reader is visible.
  queueMicrotask(() => {
    revealingReader = false;
    if (!disposed) layoutReading(true);
  });
}
function waitingForReadingPassage(reader) {
  const bookmark = readings.get(readingKey(reader))?.anchor;
  const savedPassage = bookmark && readingAnchor(reader, bookmark.key);
  let passage = savedPassage;
  if (!passage) {
    const messages = reader.querySelectorAll('[data-reading-anchor]');
    passage = messages[messages.length - 1];
  }
  const pending = passage?.querySelector('.markdown[data-markdown-parsing]');
  if (!pending) return false;
  const markdown = renderer.nodeRecords.get(pending)?.markdown;
  const waitForPassage = Boolean(savedPassage) || markdown?.sourceComplete;
  if (markdown) markdown.prioritizeReadingPassage(waitForPassage ? markdown.text.length : 0);
  // A saved offset or a completed reply's end may be beyond the first
  // Markdown batch. Only an open reply can start at its available prefix.
  return waitForPassage || !pending.hasChildNodes();
}
function layoutReading(initialOnly = false) {
  const modal = activeModal();
  for (const node of surface.querySelectorAll('[data-reading-root="true"]')) {
    if (modal && !modal.contains(node)) continue;
    const locating = pendingHistoryLocation && historyReaderOwns(node, pendingHistoryLocation);
    const generation = node.dataset.readerGeneration;
    const completing = node.hasAttribute('data-reading-initial');
    if (initialOnly && readingVisits.get(node) === generation && !locating && !completing) continue;
    if (readingVisits.get(node) !== generation || locating || completing) {
      const loading = locating || (!currentHistoryLocation(node) && waitingForReadingPassage(node));
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
    const dimensions = readingDimensions(node);
    const signature = JSON.stringify([node.dataset.readerGeneration, dimensions, dock?.getBoundingClientRect().height ?? 0,
      bookmarkNode ? bookmarkNode.getBoundingClientRect().top - readingTop(node) + node.scrollTop : null,
      hit ? hit.top - readingTop(node) + node.scrollTop : null]);
    if (readingLayouts.get(node)?.signature === signature && node.style.getPropertyValue('scroll-padding-block-end') !== '') continue;
    readingLayouts.set(node, { dimensions, signature });
    readingStep(node.dataset.key, node, 'layout');
    if (completing && location) revealHistoryLocation(location);
  }
}
function outsideDialog(event, dialog) {
  if (!dialog.contains(event.target)) return true;
  if (event.target !== dialog) return false;
  const box = dialog.getBoundingClientRect();
  return event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom;
}
let backdropPress = null;
function rememberBackdropPress(event) {
  if (event.isPrimary && event.button === 0) {
    for (const voice of surface.querySelectorAll('[data-voice-controls][open]')) {
      if (!voice.contains(event.target) && !renderer.nodeRecords.get(voice)?.attributes.has('open')) voice.open = false;
    }
  }
  const modal = renderer.modalRecord();
  backdropPress = event.isPrimary && event.button === 0 && modal?.metadata.layer?.outside &&
    outsideDialog(event, modal.node) ? { node: modal.node, occurrence: modal.metadata.layer.occurrence } : null;
}
function clearBackdropPress() { backdropPress = null; }
function dismiss(event) {
  const escape = event.type === 'keydown';
  const pressed = backdropPress;
  if (!escape) clearBackdropPress();
  if (event.defaultPrevented || (escape ? event.key !== 'Escape' : !pressed)) return;
  // DEFENSE: Escape belongs to the IME or an open select before its enclosing dialog.
  if (escape && (event.isComposing || event.keyCode === 229 || renderer.composing.has(event.target) ||
      (CSS.supports('selector(select:open)') && event.target.closest?.('select:open')))) return;
  const modal = renderer.modalRecord();
  const dismissal = modal?.events.find(binding => binding.kind === 'dismiss');
  if (!dismissal || !(escape ? modal.metadata.layer.escape :
      pressed.node === modal.node && sameGeneration(pressed.occurrence, modal.metadata.layer.occurrence) && outsideDialog(event, modal.node)) || !admitted(modal.generation)) return;
  event.preventDefault();
  dispatch({ ...renderer.input(modal, dismissal.action), value: escape ? 'escape' : 'outside' });
}
document.addEventListener('keydown', dismiss);
document.addEventListener('pointerdown', rememberBackdropPress);
document.addEventListener('pointercancel', clearBackdropPress);
document.addEventListener('click', dismiss);

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
  toolActivity.replace([]);
  let ready = false;
  let streamNotices = [];
  try {
    // A journal namespace change ends the old subscription; the authenticated
    // connection observes a fresh snapshot and binds the new namespace.
    while (!disposed && connection === controller && !controller.signal.aborted) await observeConnection({
      request: (_url, signal, initial) => readBrowserState(signal, initial),
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
        if (value.type === 'tool_activity') {
          if (value.namespace === publication.namespace) toolActivity.observe(value);
          return false;
        }
        if (value.type === 'stream-state' && value.namespace === publication.namespace)
          toolActivity.replace(Array.isArray(value.tool_activity) ? value.tool_activity : []);
        if (value.type === 'selvedge-update') {
          showUpdateStatus(value);
          return false;
        }
        if (value.type === 'workflow_request_received') {
          const pending = workflowReceipts.get(value.launch_id);
          if (pending && pending.namespace === value.namespace)
            dispatch({ type: 'completion_received', ticket: pending.ticket });
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
      commandReply: requestId => browserCommandReplies.get(requestId),
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
let hoveredDropStage = null;
function showCardDropStage(stage) {
  if (hoveredDropStage === stage) return;
  hoveredDropStage?.removeAttribute('data-card-drop-hover');
  hoveredDropStage = stage;
  hoveredDropStage?.setAttribute('data-card-drop-hover', '');
}
surface.addEventListener('scroll', event => {
  if (event.target === boardTrack) updateBoardScroll();
}, true);
surface.addEventListener('click', event => {
  const button = event.target.closest?.('[data-board-scroll]');
  if (!boardTrack || !button || button.getAttribute('aria-disabled') === 'true') return;
  scrollBoard(button.dataset.boardScroll === 'next' ? 1 : -1);
});
surface.addEventListener('change', event => {
  const select = event.target.closest?.('[data-board-stage-jump]');
  if (!boardTrack || !select?.value) return;
  const lane = boardTrack.querySelector(`[data-board-stage="${CSS.escape(select.value)}"]`);
  if (lane) boardTrack.scrollBy({
    left: lane.getBoundingClientRect().left - boardTrack.getBoundingClientRect().left - boardTrack.clientLeft,
  });
  select.value = '';
});
surface.addEventListener('keydown', event => {
  // DEFENSE: WebKit does not scroll the focused board region on arrow keys.
  if (!event.defaultPrevented && !event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey &&
      (event.key === 'ArrowLeft' || event.key === 'ArrowRight') &&
      event.target === boardTrack && boardTrack.scrollWidth > boardTrack.clientWidth) {
    event.preventDefault();
    scrollBoard(event.key === 'ArrowRight' ? 1 : -1);
  }
  if (event.key !== 'Escape' || event.defaultPrevented || event.isComposing || event.keyCode === 229 ||
      renderer.composing.has(event.target)) return;
  const voice = event.target.closest('[data-voice-controls][open]');
  if (voice) {
    voice.open = false;
    voice.querySelector('summary').focus({ preventScroll: true });
    event.preventDefault();
    return;
  }
  for (const node of surface.querySelectorAll(':is([data-help],[data-overflow-help]):is(:hover,:focus-visible)')) node.setAttribute('data-help-dismissed', '');
});
for (const name of ['pointerout', 'focusout']) surface.addEventListener(name, event => {
  const node = event.target.closest?.('[data-help-dismissed]');
  if (node && !node.contains(event.relatedTarget)) node.removeAttribute('data-help-dismissed');
});
// The DOM supplies clipping and responsive visibility. A button's existing help
// takes precedence so the measured label uses the same visual channel.
for (const name of ['pointerover', 'focusin']) surface.addEventListener(name, event => {
  const button = event.target.closest?.('button');
  if (button) {
    if (button.hasAttribute('data-help') || button.getAttribute('aria-busy') === 'true') {
      button.removeAttribute('data-overflow-help');
      return;
    }
    const label = Array.from(button.querySelectorAll('[data-overflow-label]')).find(node =>
      node.scrollWidth > node.clientWidth || !node.getClientRects().length);
    if (label) button.dataset.overflowHelp = label.dataset.overflowLabel;
    else button.removeAttribute('data-overflow-help');
    return;
  }
  const label = event.target.closest?.('[data-overflow-label]');
  if (label && matchMedia('(prefers-reduced-motion: reduce)').matches && label.scrollWidth > label.clientWidth) {
    label.title = label.dataset.overflowLabel;
  }
});
for (const name of ['pointerout', 'focusout']) surface.addEventListener(name, event => {
  const button = event.target.closest?.('button[data-overflow-help]');
  if (button && !button.contains(event.relatedTarget)) {
    if (name === 'focusout' ? !button.matches(':hover') : !button.matches(':focus-visible')) {
      button.removeAttribute('data-overflow-help');
    }
  }
  const label = event.target.closest?.('[data-overflow-label][title]');
  if (label && !label.contains(event.relatedTarget)) label.removeAttribute('title');
});
surface.addEventListener('dragstart', event => {
  const node = event.target.closest?.('[data-card-id][draggable="true"]');
  const record = node && renderer.records.get(node.dataset.key);
  if (!record || !admitted(record.generation)) return;
  draggedCard = { record, hover: null };
  event.dataTransfer.setData('application/x-selvedge-card', node.dataset.cardId);
  event.dataTransfer.effectAllowed = 'move';
});
function observedCardPlacement(source, target) {
  const generation = source?.generation;
  if (!target || !source?.metadata.place_action || !admitted(generation)) return null;
  const input = { ...source.metadata.place_action, generation, value: target.dataset.dropTarget };
  return acceptsElement(input) ? input : null;
}
surface.addEventListener('dragover', event => {
  if (!draggedCard) return;
  const target = event.target.closest?.('[data-drop-target]');
  const { record, hover } = draggedCard;
  if (!hover || hover.target !== target || hover.state !== state || hover.publication !== publication)
    draggedCard.hover = { target, state, publication, allowed: Boolean(observedCardPlacement(record, target)) };
  const allowed = draggedCard.hover.allowed;
  showCardDropStage(allowed ? target.closest('[data-board-stage]') : null);
  if (allowed) event.preventDefault();
});
surface.addEventListener('dragleave', event => {
  if (hoveredDropStage?.contains(event.target) && !hoveredDropStage.contains(event.relatedTarget))
    showCardDropStage(null);
});
surface.addEventListener('drop', event => {
  const source = draggedCard?.record; draggedCard = null;
  showCardDropStage(null);
  const target = event.target.closest?.('[data-drop-target]');
  const input = observedCardPlacement(source, target);
  if (input) {
    event.preventDefault();
    dispatch(input);
  }
});
surface.addEventListener('dragend', () => {
  draggedCard = null;
  showCardDropStage(null);
});

async function completeCommand(effect) {
  const namespace = publication.namespace;
  const startingWorkflow = effect.command.op === 'start_workflow' || effect.command.op === 'start_ticket_workflow';
  const launch = startingWorkflow ? randomBrowserIdentifier() : null;
  const command = launch === null ? effect.command : { ...effect.command, browser_launch_id: launch };
  if (launch !== null) workflowReceipts.set(launch, { namespace, ticket: effect.ticket });
  // DEFENSE: A launch can lose its reply after submission. Report uncertainty
  // while keeping the transport open for a late receipt and retaining its ticket.
  const receiptTimer = startingWorkflow ? setTimeout(() => {
    if (publication.namespace === namespace && workflowReceipts.has(launch))
      dispatch({ type: 'completion_unknown', ticket: effect.ticket, error: '未收到启动回执，结果待确认。' });
  }, 35_000) : null;
  if (receiptTimer !== null) timers.add(receiptTimer);
  const clearReceiptTimer = () => {
    if (receiptTimer === null) return;
    clearTimeout(receiptTimer);
    timers.delete(receiptTimer);
  };
  try {
    const value = await requestCommand(command, effect.read_only ? readDeadline() : undefined, !effect.read_only,
      reply => {
        clearReceiptTimer();
        if (reply.ok) dispatch({ type: 'completion_received', ticket: effect.ticket });
      });
    if (publication.namespace === namespace && value !== undefined &&
        (launch === null || workflowReceipts.delete(launch)))
      dispatch({ type: 'completed', ticket: effect.ticket, ok: true, value });
  } catch (error) {
    // DEFENSE: A lost reply ends a read observation. The server may have
    // committed a mutation, so preserve its ticket and duplicate protection.
    if (publication.namespace === namespace && (launch === null || workflowReceipts.has(launch))) {
      dispatch(effect.read_only
        ? { type: 'completed', ticket: effect.ticket, ok: false, error: error.message }
        : { type: 'completion_failed', ticket: effect.ticket, error: error.message, body: error.body ?? null });
      if (launch !== null && error.body?.error?.code === 'command_not_submitted')
        workflowReceipts.delete(launch);
    }
  } finally {
    clearReceiptTimer();
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
  pendingAssessments.set(key, { effect, namespace, key, controller });
  if (!drainingAssessments) return drainAssessments();
}
async function drainAssessments() {
  drainingAssessments = true;
  try {
    // Keep one preview request in flight. A newer draft replaces its queued proposal.
    while (!disposed && pendingAssessments.size) {
      const [key, job] = pendingAssessments.entries().next().value;
      pendingAssessments.delete(key);
      await performAssessment(job);
    }
  } finally { drainingAssessments = false; }
}
async function performAssessment({ effect, namespace, key, controller }) {
  try {
    // DEFENSE: A stalled admission request can leave a visible action indefinitely pending.
    const value = await post('/api/assess', effect.request, AbortSignal.any([controller.signal, readDeadline()]));
    if (publication.namespace === namespace) dispatch({ type: 'command_assessed', ticket: effect.ticket, ok: true, value });
  } catch (error) {
    // DEFENSE: A newer draft assessment or page teardown cancels this superseded request.
    if (controller.signal.aborted || publication.namespace !== namespace) return;
    const message = error.name === 'TimeoutError' ? '检查超时，请重试。' : error.message;
    dispatch({ type: 'command_assessed', ticket: effect.ticket, ok: false, error: message });
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
      const body = await post('/api/browser/observation', taskObservation(effect, { kind: 'workspace-git', primary: effect.primary,
        ...(effect.environment === undefined ? {} : { environment: effect.environment }) }));
      if (body.ok === false) throw new Error(body.error);
      return body.available;
    });
    case 'cloud_repository': return settled('cloud_repository_completed', effect.ticket, async () => {
      const body = await post('/api/browser/observation', { kind: 'cloud-repository', primary: effect.primary });
      return body.available;
    });
    case 'list_directory': return settled('directory_listed', effect.ticket, async () => {
      return post('/api/browser/observation', taskObservation(effect, { kind: 'browse-directories', path: effect.path,
        ...(effect.environment === undefined ? {} : { environment: effect.environment }) }));
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
      pendingHistoryLocation = { ...effect, namespace: publication.namespace, invokingFocus: document.activeElement,
        navigationGeneration: integral(state.navigation.generation), readerGeneration: integral(effect.reader_generation).toString(),
        taskId: integral(effect.task_id).toString() };
      retryHistoryLocation();
      if (pendingHistoryLocation) layoutReading(true);
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

window.addEventListener('pageshow', event => {
  if (event.persisted) dispatch({ type: 'connect' });
});
window.addEventListener('pagehide', event => {
  cancelConversationHistoryReads();
  if (event.persisted) {
    // A cached document keeps its drafts, DOM and input listeners for Back/Forward.
    connection?.abort();
    sourceFresh = false;
    storage.flush();
    return;
  }
  if (!releaseCheckpointSaved) {
    try { saveTabSession(); }
    catch (error) {
      // DEFENSE: Storage can be disabled or full when the browser is already leaving.
      console.warn('无法保存此标签页的草稿', error);
    }
  }
  disposed = true;
  settleCommandSnapshots(true);
  document.removeEventListener('selectionchange', selectionChanged);
  document.removeEventListener('keydown', dismiss);
  document.removeEventListener('pointerdown', rememberBackdropPress);
  document.removeEventListener('pointercancel', clearBackdropPress);
  document.removeEventListener('click', dismiss);
  connection?.abort(); chatgptLogin.dispose(); audio.dispose(); toolActivity.dispose(); motion.dispose();
  editorRepair.dispose(); physical.dispose(); disposeSingleLineLabels(); renderer.dispose(); storage.flush();
  clearInterval(clockRefresh); document.removeEventListener('visibilitychange', refreshClock);
  boardTrackResize.disconnect();
  readingResize.disconnect();
  for (const timer of timers) clearTimeout(timer);
  for (const entry of codeBlocks.values()) for (const physical of entry.views.values()) physical.renderer?.dispose();
  for (const controller of transfers.values()) controller.abort();
  for (const controller of assessments.values()) controller.abort();
  pendingAssessments.clear();
  for (const node of readingMeasurements.keys()) retireReadingMeasurement(node);
  retireHistoryLocation();
  window.removeEventListener('pointerup', endReadingPointer, true);
  window.removeEventListener('pointercancel', endReadingPointer, true);
  for (const resource of resources) URL.revokeObjectURL(resource);
  if (layoutFrame !== null) cancelAnimationFrame(layoutFrame);
  if (readingLayoutFrame !== null) cancelAnimationFrame(readingLayoutFrame);
  if (measurementFrame !== null) cancelAnimationFrame(measurementFrame);
  if (measurementTask !== null) clearTimeout(measurementTask);
});
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
