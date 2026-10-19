import * as Bend from './generated/browser-model.mjs';
import { boundary } from './model-boundary.mjs';
import { bendValue, bendTag, decodeBendValue, encodeBendValue } from './bend-value.mjs';
import { Renderer, list } from './renderer.mjs';
import { MarkdownFenceObserver } from './markdown-fences.mjs';
import { scheduleDisplay, cancelDisplay } from './markdown.mjs';
import { InteractiveSnapshotStorage } from './interactive-storage.mjs';
import { PresentationMotion } from './presentation-motion.mjs';
import { observeConnection } from './connection.mjs';
import { editorKeyboard, keyObservation, scalarSelection, applyScalarSelection } from './keyboard.mjs';
import { appearanceObservation, persistAppearance } from './appearance.mjs';
import { createTextMeasurer } from './text-measurement.mjs';
import { createPhysicalMeasurer } from './physical-measurement.mjs';
import { parseJson, tokenizeJsonValue } from './json-tokens.mjs';
import { createLayoutRevealer } from './layout-reveal.mjs';

const bool = enabled => Boolean(enabled);
const linked = items => items.reduceRight((tail, head) => bendValue('Con', { head, tail }), bendValue('Nil'));
function json(input) {
  if (input === null) return bendValue('bendlib/json.Null');
  if (typeof input === 'boolean') return bendValue('bendlib/json.Boolean', { value: bool(input) });
  if (typeof input === 'number') return bendValue('bendlib/json.Number', { lexeme: String(input) });
  if (typeof input === 'string') return bendValue('bendlib/json.Text', { value: input });
  if (Array.isArray(input)) return bendValue('bendlib/json.Array', { items: linked(input.map(json)) });
  return bendValue('bendlib/json.Object', { fields: linked(Object.entries(input).map(([name, item]) => bendValue('bendlib/json.Field', { name, value: json(item) }))) });
}
function showJson(input) {
  switch (bendTag(input)) {
    case 'Null': return 'null';
    case 'Boolean': return input.value ? 'true' : 'false';
    case 'Number': return input.lexeme;
    case 'Text': return JSON.stringify(input.value);
    case 'Array': return `[${list(input.items).map(showJson).join(',')}]`;
    case 'Object': return `{${list(input.fields).map(field => `${JSON.stringify(field.name)}:${showJson(field.value)}`).join(',')}}`;
  }
}
const root = document.getElementById('surface');
const revealLayoutTargets = createLayoutRevealer(root);
let textMeasurementScope = root;
let textMeasurer = createTextMeasurer(textMeasurementScope);
let state = Bend.initial(Bend.empty(), 0n);
let connection;
let revision = 0;
let dragged = null;
let renderQueued = false;
let renderDepth = 0;
let renderedGeneration = null;
let displayedFrameRequest = null;
let requestedFrameGeneration = null;
let pendingFocus = [];
let drainingFocus = false;
let applyingFocus = false;
let focusAttemptRevision = 0;
let physicalRevision = 0;
let physicalActive = false;
let physicalQueued = null;
let physicalScheduled = false;
let disposed = false;
let clockTimer = null;
let observedClock = null;
let codeObservationGroups = new Map();
let codeObservationScheduled = false;
const feedbackTimers = new Set();
const interactiveObservers = new Map();
const interactiveParseJobs = new Map();
const snapshotPolicy = Bend.interactive_storage_policy();
const interactiveStorage = new InteractiveSnapshotStorage({ maximumDocuments: Number(snapshotPolicy.maximum_documents), maximumBytes: Number(snapshotPolicy.maximum_bytes) });
const presentationMotion = new PresentationMotion(root);
let storeNamespace = '';
let sourceFresh = false;
let geometryFrame = null;
let displayedGeometry = null;
const physicalMeasurer = createPhysicalMeasurer({ surface: root, bend: Bend, onChange: geometryChanged });
const files = new Map();
const transfers = new Map();
const resources = new Set();
const streams = new Map();
const renderer = new Renderer(root, {
  fieldSessionInitial: () => Bend.field_session_initial(),
  fieldSessionStep: (event, record) => Bend.field_session_step(event, record),
  event(binding, event, node, composing) {
    switch (bendTag(binding)) {
      case 'Activate': event.preventDefault(); captureAnchor(binding.key, node); commit(Bend.activate(binding.key, state)); break;
      case 'EditText': commit(Bend.edit_text(binding.key, node.value, state)); observeEditorSelection(node); break;
      case 'EditStructuredText': {
        let parsed = bendValue('None');
        try { parsed = bendValue('Some', { value: json(JSON.parse(node.value)) }); }
        catch (error) {
          // DEFENSE: A user can leave structured text as incomplete JSON while editing; Bend receives the raw draft and no parsed value.
          if (!(error instanceof SyntaxError)) throw error;
        }
        commit(Bend.edit_structured_text(binding.key, node.value, parsed, state));
        break;
      }
      case 'ConfirmText': commit(Bend.confirm_text(binding.key, event.key, bool(event.isComposing || composing || event.keyCode === 229), bool(event.ctrlKey), bool(event.altKey), bool(event.shiftKey), bool(event.metaKey), state)); break;
      case 'EditToggle': commit(Bend.edit_toggle(binding.key, bool(node.checked), state)); break;
      case 'SelectFiles':
        for (const file of node.files) {
          const handle = crypto.randomUUID(); files.set(handle, file);
          commit(Bend.attach(binding.key, bendValue('interaction/services/MODEL.SelectedFile', { handle, name: file.name, mime: file.type, bytes: file.size }), state));
        }
        node.value = ''; break;
      case 'DragCard': dragged = binding.key; event.dataTransfer?.setData('text/plain', binding.key); break;
      case 'DropCard': if (dragged) commit(Bend.place(dragged, binding.key, state)); dragged = null; break;
      case 'SelectDestination': if (node.value) { captureAnchor(binding.key, node); commit(Bend.place(binding.key, node.value, state)); } break;
      case 'PlaceCard': event.preventDefault(); captureAnchor(binding.key, node); commit(Bend.place(binding.key, binding.target, state)); break;
    }
  },
  codeKey: (source, ordinal) => Bend.code_dom_key(source, ordinal),
  markdownComplete: source => Bend.markdown_complete(source ? bendValue('Some', { value: source }) : bendValue('None')),
  codeSource(source, ordinal, text, generation, source_value) {
    if (disposed) return;
    const sourceKey = Bend.code_key(source, 0n);
    let versions = codeObservationGroups.get(sourceKey);
    if (!versions) { versions = new Map(); codeObservationGroups.set(sourceKey, versions); }
    let batch = versions.get(source_value);
    if (!batch) { batch = { generation, entries: new Map() }; versions.set(source_value, batch); }
    batch.entries.set(Bend.code_key(source, ordinal), bendValue('browser/document/MODEL.Observation', { identity: bendValue('interaction/conversation/CODE.Identity', { source, ordinal }), text, source_value }));
    if (!codeObservationScheduled) {
      codeObservationScheduled = true;
      queueMicrotask(flushCodeObservations);
    }
  },
  changed: geometryChanged,
});
function flushCodeObservations() {
  codeObservationScheduled = false;
  const groups = codeObservationGroups;
  codeObservationGroups = new Map();
  if (disposed) return;
  // NOTE: Rendering during commit may enqueue another batch; it must retain its own observations.
  for (const versions of groups.values()) {
    for (const { generation, entries } of versions.values()) {
      commit(Bend.code_sources(generation, linked([...entries.values()]), state));
    }
  }
}
function measurementSpec(spec) {
  let available_width;
  switch (bendTag(spec.available_width)) {
    case 'None': available_width = null; break;
    case 'Some': available_width = Number(spec.available_width.value); break;
  }
  return {
    key: spec.key, text: spec.text, reference_text: spec.reference_text,
    fontFamily: spec.font_family, fontSize: Number(spec.font_size),
    lineHeight: Number(spec.line_height),
    fontWeight: Number(spec.font_weight),
    whiteSpace: spec.white_space, overflowWrap: spec.overflow_wrap, wordBreak: spec.word_break,
    available_width,
  };
}
function measurementMetric(metric) {
  return bendValue('browser/appearance/TYPOGRAPHY.Metric', {
    key: metric.key,
    minimum_width: BigInt(metric.minimum_width),
    preferred_width: BigInt(metric.preferred_width),
    constrained_height: BigInt(metric.constrained_height),
    reference_advance: BigInt(metric.reference_advance),
  });
}
function render() {
  renderDepth++;
  try { renderPublication(); } finally { renderDepth--; }
}
function renderPublication() {
  const effects = [];
  const scope = root.matches('.native-application') ? root : root.querySelector('.native-application') ?? root;
  if (scope !== textMeasurementScope) {
    textMeasurementScope = scope;
    textMeasurer = createTextMeasurer(scope);
  }
  const budget = Number(Bend.measurement_budget(state));
  for (let round = 0; round < budget; round += 1) {
    const plan = Bend.measurement_plan(state);
    const specifications = list(plan.specifications);
    if (!specifications.length) break;
    const metrics = textMeasurer.measure(specifications.map(measurementSpec));
    const decision = Bend.measurements(bendValue('browser/appearance/FONT.Observation', {
      generation: plan.generation, metrics: linked(metrics.map(measurementMetric)),
    }), state);
    state = decision.state;
    effects.push(...list(decision.effects));
  }
  const publication = Bend.publication(renderedGeneration ?? 0n, state);
  renderer.presentationPending = Bend.display_pending(state);
  root.dataset.displayPending = String(renderer.presentationPending);
  root.dataset.sourcesFresh = String(sourceFresh);
  pendingFocus = pendingFocus.filter(physical => physical.ticket === Bend.focus_ticket(state));
  switch (bendTag(publication)) {
    case 'KeepPublished': break;
    case 'Publish': {
      const ticket = Bend.focus_ticket(state);
      const before = observedFocus();
      renderer.render(publication.document, publication.generation);
      revealLayoutTargets();
      const after = observedFocus();
      const focusRevision = focusAttemptRevision;
      const feedback = Bend.publication_focus_feedback(publication, ticket, before, after);
      if (bendTag(feedback) === 'Some') queueMicrotask(() => {
        if (!disposed && focusRevision === focusAttemptRevision) platform(feedback.value);
      });
      renderedGeneration = publication.generation > 0n ? publication.generation : null;
      // Publication establishes the baseline; only later native content reflow requests a new measurement.
      displayedGeometry = geometrySignature();
      if (renderedGeneration !== null) requestDisplayedFrame(renderedGeneration);
      retryPendingFocus();
      break;
    }
  }
  const pendingPublication = renderer.presentationPending;
  renderer.presentationPending = false;
  renderer.synchronizeFields(publication.fields);
  renderer.presentationPending = pendingPublication;
  presentationMotion.refresh();
  root.dataset.renderInspection = JSON.stringify(encodeBendValue(Bend.render_inspection(state)));
  root.dataset.renderStatus = Bend.render_status(state);
  root.dataset.renderViolations = JSON.stringify(encodeBendValue(list(Bend.render_violations(state))));
  schedulePhysical();
  for (const effect of effects) void execute(effect);
}
function captureAnchor(key, node) {
  const box = node.getBoundingClientRect();
  const left = Math.round(box.left); const top = Math.round(box.top);
  const right = Math.round(box.right); const bottom = Math.round(box.bottom);
  const origin = amount => bendValue(amount < 0 ? 'browser/layout/GEOMETRY.Backward' : 'browser/layout/GEOMETRY.Forward', { distance: BigInt(Math.abs(amount)) });
  const width = BigInt(Math.max(0, right - left));
  const height = BigInt(Math.max(0, bottom - top));
  commit(Bend.capture_anchor(key, origin(left), origin(top), width, height, state));
}
function geometrySignature() {
  return [...root.querySelectorAll('[data-native-key]')].filter(node => !node.closest('[aria-hidden="true"]')).map(node => {
    const box = node.getBoundingClientRect();
    return [node.dataset.nativeKey, box.width, box.height, node.scrollWidth, node.scrollHeight];
  }).map(parts => JSON.stringify(parts)).join(';');
}
function geometryChanged() {
  if (disposed || renderQueued || renderedGeneration === null) return;
  renderQueued = true;
  geometryFrame = requestAnimationFrame(() => {
    geometryFrame = null;
    renderQueued = false;
    const signature = geometrySignature();
    if (signature === displayedGeometry) return;
    displayedGeometry = signature;
    commit(Bend.remeasure(state));
  });
}
function schedulePhysical() {
  if (disposed || physicalActive) return;
  const request = Bend.measurement_request(state);
  physicalQueued = bendTag(request) === 'Some'
    ? { plan: request.value.plan, ticket: request.value.ticket, revision: physicalRevision } : null;
  if (!physicalQueued || physicalScheduled) return;
  physicalScheduled = true;
  queueMicrotask(runPhysical);
}
async function runPhysical() {
  physicalScheduled = false;
  if (disposed || physicalActive || !physicalQueued) return;
  const batch = physicalQueued;
  physicalQueued = null;
  physicalActive = true;
  try {
    let receipt;
    try { receipt = await physicalMeasurer.measure(batch.plan); }
    catch (error) {
      // DEFENSE: Awaited font/parser work can be cancelled by a newer publication; report only a still-owned failure.
      if (!disposed && batch.revision === physicalRevision && error.name !== 'AbortError') {
        commit(Bend.physical_measurement_failed(batch.ticket, String(error), state));
      }
      return;
    }
    // DEFENSE: A publication or page teardown can invalidate this batch while native measurements await fonts or Markdown.
    if (disposed || batch.revision !== physicalRevision) return;
    commit(Bend.physical_measured(batch.ticket, linked(tokenizeJsonValue(parseJson(receipt))), state));
  } finally {
    physicalActive = false;
    schedulePhysical();
  }
}

function observedFocus() {
  nativeLinks();
  const node = document.activeElement;
  if (!node || node === document.body || !root.contains(node)) return bendValue('None');
  const anchor = nativeAnchor(node);
  if (anchor) {
    const contentOwner = nativeContentOwner(anchor);
    if (contentOwner && anchor.dataset.nativeLinkKey) return bendValue('Some', {
      value: bendValue('browser/focus/MODEL.Content', { owner: contentOwner, identity: anchor.dataset.nativeLinkKey }),
    });
    return bendValue('None');
  }
  const identity = owner(node);
  return identity ? bendValue('Some', { value: bendValue('browser/focus/MODEL.Product', { identity }) }) : bendValue('None');
}
function sameFocus(target, observed) {
  if (bendTag(observed) !== 'Some' || bendTag(target) !== bendTag(observed.value)) return false;
  return target.identity === observed.value.identity && (bendTag(target) !== 'Content' || target.owner === observed.value.owner);
}
function applyFocus(physical) {
  // DEFENSE: Focus effects can execute after a newer focus request has replaced their ticket.
  if (physical.ticket !== Bend.focus_ticket(state)) return;
  pendingFocus.push(physical);
  retryPendingFocus();
}
function retryPendingFocus() {
  if (disposed || drainingFocus || document.visibilityState !== 'visible') return;
  drainingFocus = true;
  try {
    while (pendingFocus.length) {
      const physical = pendingFocus[0];
      // DEFENSE: Publication can replace focus ownership while older targets are still awaiting creation.
      if (physical.ticket !== Bend.focus_ticket(state)) { pendingFocus.shift(); continue; }
      const target = physical.target;
      const node = bendTag(target) === 'Product' ? renderer.target(target.identity)
        : nativeLinks().find(anchor => nativeContentOwner(anchor) === target.owner && anchor.dataset.nativeLinkKey === target.identity);
      if (!node) break;
      // DEFENSE: Keep effect order while publication prepares a missing target. A later
      // focus must not replace an earlier request that also exposes its target.
      focusAttemptRevision++;
      applyingFocus = true;
      try {
        node.scrollIntoView({ block: 'nearest', inline: 'nearest' });
        node.focus({ preventScroll: false });
      } finally { applyingFocus = false; }
      const observed = observedFocus();
      const confirmed = sameFocus(target, observed);
      if (confirmed) pendingFocus.shift();
      platform(bendValue('browser/runtime/PLATFORM.FocusApplied', { ticket: physical.ticket, target, observed }));
      if (!confirmed) break;
    }
  } finally { drainingFocus = false; }
}

function commit(decision) {
  if (Bend.physical_invalidated(state, decision.state)) {
    physicalRevision++;
    physicalQueued = null;
    physicalMeasurer.cancel();
  }
  state = decision.state;
  const acceptedNamespace = Bend.store_namespace(state);
  if (acceptedNamespace !== storeNamespace) streams.clear();
  storeNamespace = acceptedNamespace;
  revision = Number(Bend.accepted_sequence(state));
  sourceFresh = Bend.source_fresh(state);
  render();
  for (const effect of list(decision.effects)) void execute(effect);
}
function step(input) { commit(Bend.step(input, state)); }
function native(input) { step(bendValue('browser/runtime/SEMANTICS.Native', { input })); }
function platform(input) { native(bendValue('browser/MODEL.PlatformInput', { input })); }
function product(input) { platform(bendValue('browser/runtime/PLATFORM.ProductInput', { input })); }
function observeClock() {
  if (disposed) return;
  const now = Math.floor(Date.now() / 1000);
  // DEFENSE: The system clock can be set before 1970 or beyond the board protocol's unsigned 32-bit timestamp range.
  if (!Number.isSafeInteger(now) || now < 0 || now > 0xffff_ffff) {
    throw new RangeError('The clock is outside the native board timestamp range');
  }
  if (now === observedClock) return;
  product(bendValue('interaction/MODEL.Clock', { now }));
  observedClock = now;
}
function clockVisibilityChanged() {
  if (document.visibilityState === 'visible') observeClock();
}
function requestScope(authentication = null, controller = connection ?? null, bound = false) {
  return { namespace: storeNamespace, sequence: revision, connectionTicket: controller?.connectionTicket ?? 0n, controller, authentication, bound };
}
function currentRequest(scope) {
  return !disposed && scope.controller === (connection ?? null) && !scope.controller?.signal.aborted;
}
function requestError(reason, scope) {
  const error = reason;
  error.requestScope ??= scope;
  return error;
}
function requireCurrentRequest(scope) {
  // DEFENSE: Authentication and watch reads may resume after a newer connection replaces their abort controller.
  if (!currentRequest(scope)) throw requestError(new DOMException('Request was superseded', 'AbortError'), scope);
}
function networkFailed(reason, scope = reason?.requestScope) {
  // DEFENSE: Auth failure can be seen by both the HTTP request and its effect; an old/already-reported request must not disconnect the current session.
  if (!scope || !currentRequest(scope) || reason?.networkReported) return;
  const error = requestError(reason, scope);
  error.networkReported = true;
  commit(Bend.network_failed(scope.namespace, BigInt(scope.sequence), scope.connectionTicket, error.message,
    error.status === 401 || error.status === 403,
    scope.authentication === null ? bendValue('None') : bendValue('Some', { value: scope.authentication }), state));
}
async function request(url, options = {}, scope = requestScope()) {
  let response;
  try {
    // Watch and authentication reads share the controller; other effects keep their own cancellation and tickets.
    if (scope.bound) requireCurrentRequest(scope);
    response = await fetch(url, { ...options, credentials: 'same-origin',
      signal: options.signal ?? (scope.bound ? scope.controller?.signal : undefined) });
    if (scope.bound) requireCurrentRequest(scope);
    const body = await response.json();
    if (scope.bound) requireCurrentRequest(scope);
    // DEFENSE: Authentication, command and filesystem endpoints can return non-success HTTP statuses.
    if (!response.ok) {
      const error = new Error(body.error?.message ?? body.error ?? `HTTP ${response.status}`);
      error.body = body;
      throw error;
    }
    return body;
  } catch (reason) {
    // DEFENSE: Fetch, response JSON decoding or controller cancellation can fail before an HTTP request produces a usable result.
    const error = requestError(reason, scope);
    if (response) error.status ??= response.status;
    // DEFENSE: Revoked browser authentication must disable external actions immediately.
    if (error.status === 401 || error.status === 403) networkFailed(error);
    throw error;
  }
}
function interactiveInput(input) {
  product(bendValue('interaction/MODEL.InterfaceInput', { input: bendValue('interaction/TYPES.Interactive', { input }) }));
}
function snapshot(body, expectedNamespace) {
  commit(Bend.snapshot_environment(expectedNamespace, body.namespace, BigInt(body.sequence), decodeBendValue(body.program), state));
  streamFacts();
}
function post(url, body) { return request(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body }); }
function result(ok, payload) { return ok ? bendValue('Done', { value: payload }) : bendValue('Fail', { error: payload }); }
function observeInteractiveMarkdown(document) {
  const key = Bend.markdown_source_key(document.source);
  let entry = interactiveObservers.get(key);
  if (!entry) {
    entry = { document, observer: null };
    entry.observer = new MarkdownFenceObserver({
      onFence(record) {
        if (disposed || interactiveObservers.get(key) !== entry) return;
        const observation = bendValue('interaction/interactive_markdown/DOCUMENTS.FenceObservation', {
          key, epoch: record.epoch, revision: record.inputRevision,
          ordinal: record.ordinal, kind: record.kind, info: record.info,
          info_complete: record.infoComplete, code: record.code, closed: record.closed,
          input_prefix: record.inputPrefix,
        });
        queueMicrotask(() => {
          if (!disposed && interactiveObservers.get(key) === entry) {
            product(bendValue('interaction/MODEL.InterfaceInput', { input: bendValue('interaction/TYPES.ApplicationInput', {
              input: bendValue('interaction/session/MODEL.InteractiveFenceObserved', { observation }),
            }) }));
          }
        });
      },
    });
    interactiveObservers.set(key, entry);
  }
  entry.document = document;
  entry.observer.sync({ text: document.text, epoch: document.epoch, revision: document.revision,
    ending: bendTag(document.ending).toLowerCase() });
}
function interactiveSettled(effect, success, message = '') {
  if (disposed) return;
  interactiveInput(bendValue('interaction/interactive_markdown/TYPES.EffectCompleted', {
    owner: effect.owner, path: effect.path, ticket: effect.ticket, success, message,
  }));
}
function interactiveStorageFailed(effect, message) {
  if (!disposed) interactiveInput(bendValue('interaction/interactive_markdown/TYPES.StorageFailed', { owner: effect.owner, message }));
}
async function interactiveEffect(effect) {
  switch (bendTag(effect)) {
    case 'RestoreFieldBuffer':
      renderer.rejectFieldBuffer(Bend.interactive_event_key(effect.event), effect.value);
      break;
    case 'ScheduleParse': {
      const key = `${effect.owner.key}/${effect.owner.epoch}`;
      if (!interactiveParseJobs.has(key)) interactiveParseJobs.set(key, scheduleDisplay(() => {
        interactiveParseJobs.delete(key);
        if (!disposed) interactiveInput(bendValue('interaction/interactive_markdown/TYPES.ContinueParsing', { owner: effect.owner }));
      }));
      break;
    }
    case 'WriteClipboard':
      try { await navigator.clipboard.writeText(effect.text); }
      catch (error) {
        // DEFENSE: Clipboard permission or document-focus policy can reject an interactive copy action.
        if (error.name !== 'NotAllowedError') throw error;
        interactiveSettled(effect, false, String(error));
        break;
      }
      interactiveSettled(effect, true);
      break;
    case 'OpenUrl': window.open(effect.url, '_blank', 'noopener,noreferrer'); break;
    case 'LoadSnapshot': {
      let stored;
      try { stored = interactiveStorage.load(effect.owner); }
      catch (error) {
        // DEFENSE: Browser storage can deny reads or contain malformed persisted JSON; expose that failure to this document.
        if (!['SecurityError', 'SyntaxError'].includes(error.name)) throw error;
        interactiveStorageFailed(effect, String(error));
        break;
      }
      if (stored !== null) interactiveInput(bendValue('interaction/interactive_markdown/TYPES.Restored', {
        owner: effect.owner, definition: stored.definition, payload: json(stored.payload),
      }));
      break;
    }
    case 'SaveSnapshot':
      interactiveStorage.save(effect.owner, effect.definition, JSON.parse(showJson(effect.payload)),
        (success, message) => { if (!success) interactiveStorageFailed(effect, message); });
      break;
    case 'RemoveSnapshot':
      try { interactiveStorage.remove(effect.owner); }
      catch (error) {
        // DEFENSE: Browser privacy policy can deny removing this document's stored snapshot.
        if (error.name !== 'SecurityError') throw error;
        interactiveStorageFailed(effect, String(error));
      }
      break;
  }
}
async function execute(effect) {
  switch (bendTag(effect)) {
    case 'Command': {
      let body;
      try {
        body = await post('/api/browser/command', `{"command":${showJson(effect.command)}}`);
      } catch (error) {
        // DEFENSE: Commands can be rejected before submission, fail after commitment, or lose their HTTP response; retain that distinction.
        if (error.body?.error?.code === 'command_not_submitted') {
          commit(Bend.command_rejected(effect.ticket, error.body.error.message, state));
        } else if (error.body?.program && error.body?.reply) {
          const body = error.body;
          commit(Bend.completed_environment(effect.ticket, body.namespace, BigInt(body.sequence), decodeBendValue(body.program), json(body.reply), state));
        } else step(bendValue('browser/runtime/SEMANTICS.Failed', { ticket: effect.ticket, error: error.message }));
        break;
      }
      commit(Bend.completed_environment(effect.ticket, body.namespace, BigInt(body.sequence), decodeBendValue(body.program), json(body.reply), state));
      break;
    }
    case 'Service': await service(effect.effect); break;
    case 'Directories': {
      const workspace = { roots: list(effect.workspace.roots), primary_root: bendTag(effect.workspace.primary) === 'Some' ? effect.workspace.primary.value : null };
      let body;
      try { body = await post('/api/browser/observation', JSON.stringify({ kind: 'directories', workspace })); }
      catch (error) {
        // DEFENSE: Workspace discovery can fail at the HTTP/filesystem boundary; complete the pending observation with its error.
        commit(Bend.directories_completed(effect.ticket, bool(false), json({ error: error.message }), state));
        break;
      }
      commit(Bend.directories_completed(effect.ticket, bool(true), json(body), state));
      break;
    }
    case 'WorkspaceGit': {
      const available = (await post('/api/browser/observation', JSON.stringify({ kind: 'workspace-git', primary: effect.primary }))).available;
      commit(Bend.workspace_git_completed(effect.ticket, bool(available), state));
      break;
    }
    case 'PersistModelPreference': localStorage.setItem('selvedge-model-preference', JSON.stringify({ profile: effect.profile, reasoning: effect.reasoning })); break;
    case 'ObserveInteractiveMarkdown': observeInteractiveMarkdown(effect.document); break;
    case 'ForgetInteractiveMarkdown': {
      const forgotten = interactiveObservers.get(effect.key);
      if (forgotten) codeObservationGroups.delete(Bend.code_key(forgotten.document.source, 0n));
      forgotten?.observer.dispose();
      interactiveObservers.delete(effect.key);
      break;
    }
    case 'InteractiveEffect': await interactiveEffect(effect.effect); break;
    case 'BrowserEffect': await browserEffect(effect.effect); break;
    case 'RenderingFailed': console.error('Bend browser failure', JSON.stringify(encodeBendValue(effect))); break;
  }
}
async function service(effect) {
  switch (bendTag(effect)) {
    case 'Authenticate': {
      connection?.abort();
      const controller = new AbortController();
      controller.connectionTicket = effect.ticket;
      connection = controller;
      const authentication = requestScope(effect.ticket, controller, true);
      let subscription = null;
      void observeConnection({
        request: (url, signal, initial) => request(url, { signal },
          initial ? authentication : requestScope(null, controller, true)),
        fetchEvents: (url, signal) => {
          subscription = requestScope(null, controller, true);
          return fetch(url, { credentials: 'same-origin', signal });
        },
        signal: controller.signal,
        current: () => currentRequest({ controller }),
        namespace: () => storeNamespace,
        sequence: () => revision,
        snapshot: (body, initial) => {
          if (initial) {
            commit(Bend.authenticated_snapshot(authentication.namespace, body.namespace,
              BigInt(body.sequence), decodeBendValue(body.program), effect.ticket, state));
          } else snapshot(body, subscription.namespace);
        },
        ready() {},
        refreshNeeded: notice => Bend.commit_refresh_needed(json(notice), state),
        notice: streamNotice,
        publish: streamFacts,
      }).catch(error => {
        // DEFENSE: Failed fetch/SSE decoding or an ended event stream must update the current connection's Bend service state.
        if (!currentRequest({ controller })) return;
        const scope = error.requestScope ?? (subscription ? { ...subscription, sequence: revision } : authentication);
        networkFailed(requestError(error, scope));
      });
      break;
    }
    case 'SessionReady': break;
    case 'SessionEnded': connection?.abort(); break;
    case 'ScheduleReconnect': {
      if (disposed) break;
      const timer = setTimeout(() => {
        feedbackTimers.delete(timer);
        if (!disposed) product(bendValue('interaction/MODEL.RetryConnection', { ticket: effect.ticket }));
      }, Number(effect.delay_ms));
      feedbackTimers.add(timer);
      break;
    }
    case 'StoreAppearance': {
      persistAppearance(localStorage, effect.appearance);
      break;
    }
    case 'Upload': {
      const controller = new AbortController(); transfers.set(effect.ticket, controller);
      const file = files.get(effect.file.handle);
      let body;
      try {
        body = await request(`/api/board/attachments?name=${encodeURIComponent(file.name)}`, { method: 'POST', body: file, signal: controller.signal });
      } catch (error) {
        // DEFENSE: Upload fetches can fail or be cancelled; complete the transfer ticket with its reported failure.
        product(bendValue('interaction/MODEL.Uploaded', { ticket: effect.ticket, result: result(false, error.message) }));
        break;
      } finally { transfers.delete(effect.ticket); }
      product(bendValue('interaction/MODEL.Uploaded', { ticket: effect.ticket, result: result(true, bendValue('features/board/MODEL.Attachment', body.result)) }));
      files.delete(effect.file.handle);
      break;
    }
    case 'CancelTransfer': transfers.get(effect.ticket)?.abort(); transfers.delete(effect.ticket); break;
    case 'ReadDirectories': {
      let body;
      try { body = await post('/api/browser/observation', JSON.stringify({ kind: 'browse-directories', path: effect.path })); }
      catch (error) {
        // DEFENSE: Folder listing HTTP requests can fail; settle the pending picker with the observed error.
        commit(Bend.directory_listed(effect.ticket, bool(false), json({ error: error.message }), state));
        break;
      }
      commit(Bend.directory_listed(effect.ticket, bool(true), json(body), state));
      break;
    }
    case 'ReadAttachment': {
      let resource;
      try {
        const response = await fetch(`/api/board/attachments/${encodeURIComponent(effect.file.id)}`, { credentials: 'same-origin' });
        // DEFENSE: Attachment download endpoints can reject inaccessible or deleted files.
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        resource = URL.createObjectURL(await response.blob()); resources.add(resource);
      } catch (error) {
        // DEFENSE: Attachment fetch/blob decoding can fail; complete the preview ticket with its reported failure.
        product(bendValue('interaction/MODEL.AttachmentRead', { ticket: effect.ticket, result: result(false, error.message) }));
        break;
      }
      product(bendValue('interaction/MODEL.AttachmentRead', { ticket: effect.ticket, result: result(true, resource) }));
      break;
    }
    case 'DownloadAttachment': {
      const response = await fetch(`/api/board/attachments/${encodeURIComponent(effect.file.id)}`, { credentials: 'same-origin' });
      // DEFENSE: Attachment download endpoints can reject inaccessible or deleted files.
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const url = URL.createObjectURL(await response.blob());
      const link = document.createElement('a'); link.href = url; link.download = effect.file.name; link.click(); setTimeout(() => URL.revokeObjectURL(url), 0); break;
    }
  }
}
const rect = node => { const r = node.getBoundingClientRect(); return bendValue('browser/controls/GEOMETRY.Rect', { left: r.left, top: r.top, right: r.right, bottom: r.bottom }); };
const owner = node => node?.closest?.('[data-native-key]')?.getAttribute('data-native-key') ?? '';
const nativeContentOwner = node => node?.closest?.('[data-native-content-owner]')?.dataset.nativeContentOwner ?? '';
function nativeLinks() {
  const counts = new Map();
  const anchors = [];
  for (const anchor of root.querySelectorAll('a[href]')) {
    const owner = nativeContentOwner(anchor);
    if (!owner) { delete anchor.dataset.nativeLinkKey; continue; }
    const href = anchor.href;
    const group = JSON.stringify([owner, href]);
    const ordinal = counts.get(group) ?? 0;
    counts.set(group, ordinal + 1);
    anchor.dataset.nativeLinkKey = JSON.stringify(['native-link', owner, href, ordinal]);
    anchors.push(anchor);
  }
  return anchors;
}
const nativeAnchor = node => node?.closest?.('a[data-native-link-key]');
const focusIdentity = node => nativeAnchor(node)?.dataset.nativeLinkKey ?? owner(node);
const hasArea = bounds => bounds.right > bounds.left && bounds.bottom > bounds.top;
function frameGeometry(node, bounds) {
  let painted = hasArea(bounds);
  // DEFENSE: Browsers without checkVisibility still use the explicit ancestor/exposure geometry checks below.
  if (node.checkVisibility) painted &&= node.checkVisibility({ opacityProperty: true, visibilityProperty: true, contentVisibilityAuto: true });
  const intersection = { left: Math.max(0, bounds.left), top: Math.max(0, bounds.top), right: Math.min(innerWidth, bounds.right), bottom: Math.min(innerHeight, bounds.bottom) };
  let scrollable = false;
  for (let ancestor = node; ancestor; ancestor = ancestor.parentElement) {
    const style = getComputedStyle(ancestor);
    if (ancestor.hidden || style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse' || style.contentVisibility === 'hidden' || Number(style.opacity) === 0) painted = false;
    if (ancestor === node) continue;
    const border = ancestor.getBoundingClientRect();
    const clip = { left: border.left + ancestor.clientLeft, top: border.top + ancestor.clientTop,
      right: border.left + ancestor.clientLeft + ancestor.clientWidth,
      bottom: border.top + ancestor.clientTop + ancestor.clientHeight };
    if (style.overflowX !== 'visible') {
      intersection.left = Math.max(intersection.left, clip.left);
      intersection.right = Math.min(intersection.right, clip.right);
    }
    if (style.overflowY !== 'visible') {
      intersection.top = Math.max(intersection.top, clip.top);
      intersection.bottom = Math.min(intersection.bottom, clip.bottom);
    }
    if ((['auto', 'scroll'].includes(style.overflowX) && ancestor.scrollWidth > ancestor.clientWidth)
      || (['auto', 'scroll'].includes(style.overflowY) && ancestor.scrollHeight > ancestor.clientHeight)) scrollable = true;
  }
  const visible = painted && hasArea(intersection);
  const control = node.tabIndex >= 0 || node.matches('button,input,select,textarea,a[href],area[href],summary,[contenteditable="true"]');
  const paintBounds = bendValue('browser/controls/GEOMETRY.Rect', { left: intersection.left, top: intersection.top,
    right: Math.max(intersection.left, intersection.right), bottom: Math.max(intersection.top, intersection.bottom) });
  return { visible, paintBounds, scrollReachable: painted && control && scrollable,
    hitOwner: visible ? focusIdentity(document.elementFromPoint((intersection.left + intersection.right) / 2, (intersection.top + intersection.bottom) / 2)) : '' };
}
function frame() {
  const anchors = nativeLinks();
  const nodes = [...root.querySelectorAll('[data-frame-key],[data-native-key],a[data-native-link-key]')];
  const elements = nodes.map(node => {
    const bounds = rect(node); const geometry = frameGeometry(node, bounds);
    const enabled = !node.disabled && !node.closest('[inert]') && node.getAttribute('aria-disabled') !== 'true';
    const tab = enabled && node.tabIndex >= 0 && (geometry.visible || geometry.scrollReachable);
    return bendValue('browser/document/RENDERED.Element', { key: node.getAttribute('data-frame-key') ?? focusIdentity(node), visible: bool(geometry.visible), enabled: bool(enabled), tab_stop: bool(tab), keyboard_reachable: bool(tab), scroll_reachable: bool(geometry.scrollReachable), bounds,
      center_hit_owner: geometry.hitOwner, paint_bounds: geometry.paintBounds });
  });
  const focused = focusIdentity(document.activeElement);
  const tabOrder = nodes.filter(node => {
    if (node.tabIndex < 0 || node.disabled || node.closest('[inert],[hidden]')) return false;
    const geometry = frameGeometry(node, rect(node));
    return geometry.visible || geometry.scrollReachable;
  });
  tabOrder.sort((a, b) => (a.tabIndex > 0 ? a.tabIndex : Infinity) - (b.tabIndex > 0 ? b.tabIndex : Infinity));
  return bendValue('browser/document/RENDERED.Frame', { viewport: bendValue('browser/controls/GEOMETRY.Rect', { left: 0, top: 0, right: innerWidth, bottom: innerHeight }), elements: linked(elements),
    focused: focused ? bendValue('Some', { value: focused }) : bendValue('None'), tab_order: linked(tabOrder.map(focusIdentity)),
    native_focus: linked(anchors.map(anchor => bendValue('browser/document/RENDERED.NativeFocus', { identity: anchor.dataset.nativeLinkKey, owner: nativeContentOwner(anchor) }))) });
}
function requestDisplayedFrame(generation) {
  requestedFrameGeneration = generation;
  if (disposed || displayedFrameRequest !== null) return;
  displayedFrameRequest = requestAnimationFrame(() => {
    displayedFrameRequest = null;
    const generation = requestedFrameGeneration;
    requestedFrameGeneration = null;
    if (!disposed && renderedGeneration === generation) {
      native(bendValue('browser/MODEL.FrameObserved', { generation, frame: frame() }));
    }
  });
}
async function browserEffect(effect) {
  if (bendTag(effect) === 'MeasureFrame') {
    if (renderedGeneration !== null) requestDisplayedFrame(renderedGeneration);
    return;
  }
  const physical = effect.effect;
  switch (bendTag(physical)) {
    case 'Focus': {
      applyFocus(physical); break;
    }
    case 'Clipboard': {
      switch (bendTag(physical.effect)) {
        case 'WriteClipboard': {
          let success = false;
          try { await navigator.clipboard.writeText(physical.effect.text); success = true; }
          catch (error) {
            // DEFENSE: Clipboard permission or document-focus policy can reject writeText; complete the ticket with visible failure feedback.
            if (error.name !== 'NotAllowedError') throw error;
          }
          product(bendValue('interaction/MODEL.ClipboardCompleted', { identity: physical.block, ticket: physical.effect.ticket, success: bool(success) }));
          break;
        }
        case 'ScheduleFeedbackExpiry': {
          if (disposed) break;
          const timer = setTimeout(() => {
            feedbackTimers.delete(timer);
            if (!disposed) product(bendValue('interaction/MODEL.ClipboardFeedbackExpired', { identity: physical.block, ticket: physical.effect.ticket }));
          }, Number(physical.effect.delay_ms));
          feedbackTimers.add(timer);
          break;
        }
      }
      break;
    }
    case 'ObserveSkillCatalog': {
      const workspace = { roots: list(physical.workspace.roots), primary_root: bendTag(physical.workspace.primary) === 'Some' ? physical.workspace.primary.value : null };
      let body;
      try { body = await post('/api/browser/observation', JSON.stringify({ kind: 'skill-catalog', workspace })); }
      catch (error) {
        // DEFENSE: The authenticated directory observation can fail at the HTTP boundary; settle its ticket with visible feedback.
        body = { ok: false, error: error.message };
      }
      commit(Bend.editor_catalog_completed(physical.key, physical.ticket, physical.workspace_key, json(body), state));
      break;
    }
    case 'SetEditorSelection': {
      const node = [...root.querySelectorAll('[data-native-editor-key]')].find(node => node.getAttribute('data-native-editor-key') === physical.key);
      // DEFENSE: Navigation can remove a composer before a committed selection effect reaches its native element.
      if (node) applyScalarSelection(node, physical.selection);
      break;
    }
    case 'ApplyReading': applyReading(physical); break;
  }
}
function readingSurface(task, generation) {
  return root.querySelector(`[data-reading-scroll][data-reading-task="${task}"][data-reading-generation="${generation}"]`);
}
function readingInput(surface, event) {
  commit(Bend.reading(BigInt(surface.dataset.readingTask), BigInt(surface.dataset.readingGeneration), event, state));
}
function anchor(surface) {
  const viewport = surface.getBoundingClientRect();
  const node = [...surface.querySelectorAll('[data-reading-key]')].find(item => { const r = item.getBoundingClientRect(); return r.bottom > viewport.top && r.top < viewport.bottom; });
  return node ? bendValue('browser/controls/GEOMETRY.Anchor', { identity: node.dataset.readingKey, offset: node.getBoundingClientRect().top - viewport.top }) : null;
}
// This tracks an in-flight physical measurement, not a second reading policy.
const readingMeasurements = new WeakMap();
const readingPointers = new Map();
const readingUserOwned = new WeakSet();
const readingCorrections = new WeakMap();
function markReadingCorrection(surface) {
  const correction = Symbol();
  readingCorrections.set(surface, correction);
  requestAnimationFrame(() => { if (readingCorrections.get(surface) === correction) readingCorrections.delete(surface); });
}
function readingOwner(surface) {
  return Object.freeze({ key: surface.dataset.nativeKey, task: surface.dataset.readingTask, generation: surface.dataset.readingGeneration });
}
function matchesReadingOwner(surface, captured) {
  return surface.dataset.nativeKey === captured.key && surface.dataset.readingTask === captured.task && surface.dataset.readingGeneration === captured.generation;
}
function retireReadingMeasurement(surface, pending) {
  if (readingMeasurements.get(surface)?.identity === pending.identity) readingMeasurements.delete(surface);
}
function currentReadingMeasurement(surface) {
  const pending = readingMeasurements.get(surface);
  if (pending && (!surface.isConnected || !matchesReadingOwner(surface, pending.owner))) {
    retireReadingMeasurement(surface, pending);
    return null;
  }
  return pending;
}
function createReadingMeasurement(surface) {
  const pending = { identity: Symbol(), owner: readingOwner(surface), frame: null, pointers: new Set() };
  readingMeasurements.set(surface, pending);
  return pending;
}
function measureUserAnchor(surface) {
  const pending = currentReadingMeasurement(surface);
  if (!pending || pending.frame !== null) return;
  pending.frame = requestAnimationFrame(() => {
    pending.frame = null;
    // DEFENSE: Keyed nodes can survive a reader change; queued work keeps its original owner.
    if (!surface.isConnected || !matchesReadingOwner(surface, pending.owner) || readingMeasurements.get(surface)?.identity !== pending.identity) {
      retireReadingMeasurement(surface, pending);
      return;
    }
    const observed = anchor(surface);
    if (pending.pointers.size === 0) retireReadingMeasurement(surface, pending);
    if (observed) commit(Bend.reading(BigInt(pending.owner.task), BigInt(pending.owner.generation), bendValue('browser/reading/MODEL.AnchorObserved', { anchor: observed }), state));
  });
}
function beginUserScroll(surface, pointerId) {
  readingUserOwned.add(surface);
  const pending = currentReadingMeasurement(surface) ?? createReadingMeasurement(surface);
  if (pointerId !== undefined) { pending.pointers.add(pointerId); readingPointers.set(pointerId, surface); }
  readingInput(surface, bendValue('browser/reading/MODEL.BeginUserScroll'));
  measureUserAnchor(surface);
}
function applyReading(physical) {
  const surface = readingSurface(physical.task, physical.generation);
  // DEFENSE: A queued reading effect may outlive the task's rendered conversation generation.
  if (!surface) return;
  const effect = physical.effect;
  switch (bendTag(effect)) {
    case 'LeaveViewport':
      markReadingCorrection(surface);
      // An instant move to the current offset cancels an earlier smooth correction.
      surface.scrollTo({ top: surface.scrollTop, left: surface.scrollLeft, behavior: 'instant' }); break;
    case 'CancelAnchorObservation': {
      const pending = currentReadingMeasurement(surface);
      if (pending) {
        if (pending.frame !== null) cancelAnimationFrame(pending.frame);
        retireReadingMeasurement(surface, pending);
        pending.pointers.clear();
      }
      for (const [pointerId, ownerSurface] of readingPointers) {
        if (ownerSurface === surface) readingPointers.delete(pointerId);
      }
      readingUserOwned.delete(surface);
      break;
    }
    case 'AlignLatest':
      markReadingCorrection(surface);
      surface.scrollTo({ top: surface.scrollHeight, behavior: effect.animate ? 'smooth' : 'instant' });
      break;
    case 'PreserveAnchor': {
      if (currentReadingMeasurement(surface)) break;
      const node = [...surface.querySelectorAll('[data-reading-key]')].find(item => item.dataset.readingKey === effect.anchor.identity);
      if (node) { markReadingCorrection(surface); surface.scrollTop += node.getBoundingClientRect().top - surface.getBoundingClientRect().top - effect.anchor.offset; } break;
    }
    case 'MeasureAnchor': {
      if (currentReadingMeasurement(surface)) { measureUserAnchor(surface); break; }
      const observed = anchor(surface); if (observed) readingInput(surface, bendValue('browser/reading/MODEL.AnchorObserved', { anchor: observed })); break;
    }
    case 'ReserveComposer': { const content = root.querySelector(`[data-reading-content][data-reading-task="${physical.task}"]`); if (content) content.style.setProperty('--reading-composer-reserve', `${effect.height}px`); break; }
  }
}
function streamFacts() {
  const facts = [...streams.values()].map(entry => ({ namespace: entry.namespace, task_id: entry.task, ticket: entry.ticket,
    parts: [...entry.parts].map(([output_index, text]) => ({ output_index, text })) }));
  commit(Bend.streams(json({ kind: 'streams', namespace: storeNamespace, streams: facts }), state));
}
function streamNotice(notice) {
  if (!Bend.stream_notice_owned(json(notice), state)) return false;
  const source = { state: [...streams.values()].map(entry => ({ namespace: entry.namespace, task_id: entry.task, ticket: entry.ticket,
    parts: [...entry.parts].map(([output_index, text]) => ({ output_index, text })) })), notice };
  const next = boundary('browser.stream_step', source);
  streams.clear();
  for (const entry of next.state) streams.set(`${entry.task_id}:${entry.ticket}`,
    { namespace: notice.namespace, task: entry.task_id, ticket: entry.ticket, parts: new Map(entry.parts.map(part => [part.output_index, part.text])) });
  return next.publish;
}

function environmentInput() {
  const fontSize = getComputedStyle(document.documentElement).fontSize;
  const pixels = Number(fontSize.slice(0, -2));
  const rootFontSizeMilli = Math.ceil(pixels * 1000);
  return bendValue('browser/MODEL.EnvironmentObserved', { environment: bendValue('browser/appearance/DESIGN.Environment', {
    viewport: bendValue('browser/appearance/DESIGN.Viewport', {
      width: BigInt(Math.floor(innerWidth)),
      height: BigInt(Math.floor(innerHeight)),
    }),
    root_font_size_milli: BigInt(rootFontSizeMilli),
    system_dark: bool(matchMedia('(prefers-color-scheme: dark)').matches),
  }) });
}
function environment() {
  physicalRevision++;
  physicalMeasurer.cancel();
  native(environmentInput());
}
window.addEventListener('resize', environment);
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', environment);
document.fonts.addEventListener('loadingdone', environment);
document.fonts.addEventListener('loadingerror', environment);
const motion = matchMedia('(prefers-reduced-motion: reduce)');
motion.addEventListener('change', () => platform(bendValue('browser/runtime/PLATFORM.MotionPreference', { reduced: bool(motion.matches) })));
root.addEventListener('focusin', () => {
  if (applyingFocus) return;
  focusAttemptRevision++;
  pendingFocus = [];
  nativeLinks();
  const anchor = nativeAnchor(document.activeElement);
  if (!anchor) { platform(bendValue('browser/runtime/PLATFORM.FocusObserved', { identity: owner(document.activeElement) })); return; }
  if (renderedGeneration === null) return;
  const generation = renderedGeneration;
  const contentOwner = nativeContentOwner(anchor);
  const identity = anchor.dataset.nativeLinkKey;
  native(bendValue('browser/MODEL.FrameObserved', { generation, frame: frame() }));
  commit(Bend.native_focus_observed(generation, contentOwner, identity, state));
});
window.addEventListener('pagehide', () => {
  disposed = true;
  pendingFocus = [];
  if (displayedFrameRequest !== null) cancelAnimationFrame(displayedFrameRequest);
  displayedFrameRequest = null;
  requestedFrameGeneration = null;
  codeObservationGroups.clear();
  codeObservationScheduled = false;
  clearInterval(clockTimer);
  document.removeEventListener('visibilitychange', clockVisibilityChanged);
  document.removeEventListener('visibilitychange', retryPendingFocus);
  window.removeEventListener('focus', retryPendingFocus);
  for (const timer of feedbackTimers) clearTimeout(timer);
  feedbackTimers.clear();
  physicalRevision++;
  for (const { observer } of interactiveObservers.values()) observer.dispose();
  interactiveObservers.clear();
  for (const job of interactiveParseJobs.values()) cancelDisplay(job);
  interactiveParseJobs.clear();
  interactiveStorage.dispose();
  presentationMotion.dispose();
  physicalMeasurer.dispose();
  if (geometryFrame !== null) cancelAnimationFrame(geometryFrame);
  connection?.abort();
  for (const resource of resources) URL.revokeObjectURL(resource);
});
const bootEffects = [];
const appearanceDecision = Bend.step(bendValue('browser/runtime/SEMANTICS.Native', {
  input: bendValue('browser/MODEL.PlatformInput', {
    input: bendValue('browser/runtime/PLATFORM.ProductInput', {
      input: appearanceObservation(localStorage),
    }),
  }),
}), state);
state = appearanceDecision.state;
bootEffects.push(...list(appearanceDecision.effects));
const storedModelPreference = JSON.parse(localStorage.getItem('selvedge-model-preference'));
if (storedModelPreference !== null) {
  // DEFENSE: Persisted model preferences must have the current profile/reasoning format; malformed storage is rejected at startup.
  if (typeof storedModelPreference.profile !== 'string' || typeof storedModelPreference.reasoning !== 'string') {
    throw new TypeError('Invalid stored model preference');
  }
  const input = bendValue('browser/runtime/SEMANTICS.Native', { input: bendValue('browser/MODEL.PlatformInput', { input: bendValue('browser/runtime/PLATFORM.ProductInput', { input: bendValue('interaction/MODEL.InterfaceInput', { input: bendValue('interaction/TYPES.ApplicationInput', { input: bendValue('interaction/session/MODEL.ModelPreferenceRestored', storedModelPreference) }) }) }) }) });
  const decision = Bend.step(input, state);
  state = decision.state;
  bootEffects.push(...list(decision.effects));
}
for (const input of [
  environmentInput(),
  bendValue('browser/MODEL.PlatformInput', { input: bendValue('browser/runtime/PLATFORM.MotionPreference', { reduced: bool(motion.matches) }) }),
]) {
  const decision = Bend.step(bendValue('browser/runtime/SEMANTICS.Native', { input }), state);
  state = decision.state; bootEffects.push(...list(decision.effects));
}
render();
for (const effect of bootEffects) void execute(effect);
observeClock();
clockTimer = setInterval(observeClock, 60_000);
document.addEventListener('visibilitychange', clockVisibilityChanged);
document.addEventListener('visibilitychange', retryPendingFocus);
window.addEventListener('focus', retryPendingFocus);
native(bendValue('browser/MODEL.Mount'));
commit(Bend.connect(state));
void document.fonts.ready.then(environment);

function editorEvent(node, event, deferDuringRender = false) {
  const key = node?.getAttribute?.('data-native-editor-key');
  if (!key) return;
  // NOTE: Reparenting a focused editor emits blur inside insertBefore; finish publication before observing that focus change.
  if (deferDuringRender && renderDepth > 0) queueMicrotask(() => {
    if (!disposed) commit(Bend.editor_event(key, event, state));
  });
  else commit(Bend.editor_event(key, event, state));
}
function observeEditorSelection(node, eventKind = 'SelectionObserved', deferDuringRender = false) {
  const key = node?.getAttribute?.('data-native-editor-key');
  if (key && typeof node.selectionStart === 'number') editorEvent(node, bendValue('browser/editor/MODEL.' + eventKind, {
    key, selection: scalarSelection(node),
  }), deferDuringRender);
}
root.addEventListener('compositionstart', event => editorEvent(event.target, bendValue('browser/editor/MODEL.CompositionChanged', { composing: bool(true) })));
root.addEventListener('compositionend', event => {
  editorEvent(event.target, bendValue('browser/editor/MODEL.CompositionChanged', { composing: bool(false) }));
  observeEditorSelection(event.target);
});
root.addEventListener('focusin', event => observeEditorSelection(event.target, 'FocusObserved', true));
root.addEventListener('focusout', event => editorEvent(event.target, bendValue('browser/editor/MODEL.DismissMention'), true));
root.addEventListener('keydown', event => {
  const key = event.target.getAttribute?.('data-native-editor-key');
  if (key) {
    const result = Bend.editor_key_event(key, keyObservation(event), state);
    if (result.handled) { event.preventDefault(); commit(result.decision); return; }
  }
  if (event.key === 'Tab' || event.key === 'Escape') {
    if (renderedGeneration === null) return;
    const result = Bend.key_event(event.key, bool(event.shiftKey), renderedGeneration, frame(), state);
    if (result.handled) event.preventDefault();
    commit(result.decision);
    return;
  }
  if (key) editorKeyboard(event,
    observation => Bend.native_editor_key(observation), input => editorEvent(event.target, input));
});
root.addEventListener('select', event => observeEditorSelection(event.target), true);
root.addEventListener('keyup', event => {
  if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key) && !event.isComposing && event.keyCode !== 229) observeEditorSelection(event.target);
});
root.addEventListener('pointerup', event => observeEditorSelection(event.target));

let layoutFrame = null;
function observeReadingLayout() {
  if (layoutFrame !== null) return;
  layoutFrame = requestAnimationFrame(() => {
    layoutFrame = null;
    for (const surface of root.querySelectorAll('[data-reading-scroll]')) {
      const dock = root.querySelector(`[data-reading-dock][data-reading-task="${surface.dataset.readingTask}"]`);
      const dockExtent = dock ? Math.max(0, surface.getBoundingClientRect().bottom - dock.getBoundingClientRect().top) : 0;
      const viewportHeight = surface.clientHeight;
      const viewportWidth = surface.clientWidth;
      const scrollHeight = surface.scrollHeight;
      const content = root.querySelector(`[data-reading-content][data-reading-task="${surface.dataset.readingTask}"]`);
      const contentRect = content ? content.getBoundingClientRect() : null;
      // Content or font reflow can change reading geometry while the dock stays fixed.
      const signature = `${dockExtent}:${viewportHeight}:${viewportWidth}:${scrollHeight}:${contentRect?.width ?? 0}:${contentRect?.height ?? 0}`;
      if (surface.dataset.observedLayout === signature) continue;
      surface.dataset.observedLayout = signature;
      readingInput(surface, bendValue('browser/reading/MODEL.LayoutChanged', { dock_extent: dockExtent, viewport_height: viewportHeight }));
    }
  });
}
const resizeObserver = new ResizeObserver(observeReadingLayout);
const observed = new WeakSet();
new MutationObserver(() => {
  for (const node of root.querySelectorAll('[data-reading-scroll],[data-reading-content],[data-reading-dock]')) if (!observed.has(node)) { observed.add(node); resizeObserver.observe(node); }
  observeReadingLayout();
}).observe(root, { childList: true, subtree: true });
function observeUserScroll(event) {
  const surface = event.target.closest('[data-reading-scroll]');
  if (surface) beginUserScroll(surface);
}
root.addEventListener('wheel', observeUserScroll, { passive: true });
root.addEventListener('touchmove', observeUserScroll, { passive: true });
root.addEventListener('keydown', event => {
  if (['PageUp', 'PageDown', 'ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key) && !event.target.matches('input,textarea,select')) observeUserScroll(event);
});
root.addEventListener('pointerdown', event => {
  const scope = Bend.active_scope(state);
  const layers = bendTag(scope) === 'Temporary'
    ? [...root.querySelectorAll('[data-layer-key]')].filter(node => !node.closest('[inert]'))
    : [];
  const layer = layers.length === 1 ? layers[0] : null;
  if (layer?.dataset.layerOutside === 'true') {
    const path = event.composedPath();
    const onTrigger = path.some(node => {
      const key = node?.getAttribute?.('data-native-key');
      return key && key === scope.restore;
    });
    if (!path.includes(layer) && !onTrigger) {
      const result = Bend.outside_event(layer.dataset.layerKey, state);
      if (result.handled) {
        event.preventDefault();
        commit(result.decision);
      }
    }
  }
  const surface = event.target.closest('[data-reading-scroll]');
  if (!surface || surface.scrollHeight <= surface.clientHeight) return;
  const rect = surface.getBoundingClientRect();
  const style = getComputedStyle(surface);
  const borderLeft = Number.parseFloat(style.borderLeftWidth);
  const borderRight = Number.parseFloat(style.borderRightWidth);
  const contentLeft = rect.left + surface.clientLeft;
  const contentRight = contentLeft + surface.clientWidth;
  const inLeftGutter = event.clientX >= rect.left + borderLeft && event.clientX < contentLeft;
  const inRightGutter = event.clientX >= contentRight && event.clientX < rect.right - borderRight;
  if ((inLeftGutter || inRightGutter) && event.clientY >= rect.top && event.clientY <= rect.bottom) beginUserScroll(surface, event.pointerId);
}, { capture: true });
function endReadingPointer(event) {
  const surface = readingPointers.get(event.pointerId);
  if (!surface) return;
  readingPointers.delete(event.pointerId);
  const pending = currentReadingMeasurement(surface);
  if (pending) { pending.pointers.delete(event.pointerId); measureUserAnchor(surface); }
}
window.addEventListener('pointerup', endReadingPointer, true);
window.addEventListener('pointercancel', endReadingPointer, true);
root.addEventListener('scroll', event => {
  if (renderedGeneration !== null) requestDisplayedFrame(renderedGeneration);
  const surface = event.target;
  if (!surface.matches?.('[data-reading-scroll]')) return;
  if (!currentReadingMeasurement(surface) && readingUserOwned.has(surface) && !readingCorrections.has(surface)) {
    createReadingMeasurement(surface);
  }
  if (currentReadingMeasurement(surface)) measureUserAnchor(surface);
}, true);
for (const node of root.querySelectorAll('[data-reading-scroll],[data-reading-content],[data-reading-dock]')) { observed.add(node); resizeObserver.observe(node); }
observeReadingLayout();

// Declared owners describe presentation interest; Bend decides action exposure.
const navigationOwner = node => node?.closest?.('[data-navigation-owner]')?.getAttribute('data-navigation-owner') ?? null;
const navigationOwnerValue = value => value === null ? bendValue('None') : bendValue('Some', { value });
let observedNavigationPointer = null;
let observedNavigationFocus = null;
function observeNavigationPointer(owner) {
  if (observedNavigationPointer === owner) return;
  observedNavigationPointer = owner;
  commit(Bend.navigation_pointer_observed(navigationOwnerValue(owner), state));
}
function observeNavigationFocus(owner) {
  if (observedNavigationFocus === owner) return;
  observedNavigationFocus = owner;
  commit(Bend.navigation_focus_observed(navigationOwnerValue(owner), state));
}
root.addEventListener('pointerover', event => observeNavigationPointer(navigationOwner(event.target)));
root.addEventListener('pointerout', event => observeNavigationPointer(navigationOwner(event.relatedTarget)));
root.addEventListener('focusin', event => observeNavigationFocus(navigationOwner(event.target)));
root.addEventListener('focusout', event => observeNavigationFocus(navigationOwner(event.relatedTarget)));
const navigationHover = matchMedia('(hover: hover)');
navigationHover.addEventListener('change', () => commit(Bend.navigation_hover_observed(bool(navigationHover.matches), state)));
commit(Bend.navigation_hover_observed(bool(navigationHover.matches), state));
