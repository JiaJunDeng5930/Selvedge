import { boundary } from './model-boundary.mjs';
import { browser, interaction } from './browser-model-boundary.mjs';
import { JsonNumber, parseJson, stringifyJson } from './json-tokens.mjs';
import { Renderer } from './renderer.mjs';
import { editorKeyboard, keyObservation, applyByteSelection } from './keyboard.mjs';
import { observeConnection } from './connection.mjs';
import { AudioRuntime } from './audio.mjs';
import { InteractiveSnapshotStorage } from './interactive-storage.mjs';
import { createLayoutRevealer } from './layout-reveal.mjs';
import { PresentationMotion } from './presentation-motion.mjs';
import { safeHref } from './markdown.mjs';
import { createPhysicalMeasurer } from './physical-measurement.mjs';

const surface = document.getElementById('surface');
const files = new Map();
const transfers = new Map();
const assessments = new Map();
const resources = new Set();
const timers = new Set();
const readings = new Map();
const codeBlocks = new Map();
const storagePolicy = interaction('interactive_storage_policy');
const storage = new InteractiveSnapshotStorage({ ...storagePolicy,
  maximumDocuments: Number(storagePolicy.maximumDocuments instanceof JsonNumber ? storagePolicy.maximumDocuments.source : storagePolicy.maximumDocuments),
  maximumBytes: Number(storagePolicy.maximumBytes instanceof JsonNumber ? storagePolicy.maximumBytes.source : storagePolicy.maximumBytes) });
const reveal = createLayoutRevealer(surface);
const motion = new PresentationMotion(surface);
let state = interaction('initial');
let world = null;
let publication = { semantic: 0, document: 0, published: 0, namespace: '', sequence: 0 };
let connection = null;
let disposed = false;
let sourceFresh = false;
let layoutFrame = null;
const ticketKey = value => stringifyJson(value);
const integral = value => BigInt(value instanceof JsonNumber ? value.source : value);

function taskObservation(effect, fields) {
  return effect.task_id === undefined ? fields : { ...fields, task_id: effect.task_id };
}

async function request(url, options = {}) {
  const response = await fetch(url, { ...options, credentials: 'same-origin' });
  const text = await response.text();
  const value = text ? parseJson(text) : null;
  // DEFENSE: Authentication failures and rejected external requests are observable service outcomes.
  if (!response.ok) {
    const error = new Error(typeof value?.error === 'string' ? value.error : value?.error?.message ?? `HTTP ${response.status}`);
    error.body = value;
    error.status = response.status;
    throw error;
  }
  return value;
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
  snapshot(body, expected);
  return body.reply;
}

function publicationEvent(event, values = {}) {
  return browser('publication', { ...publication, event, ...values });
}
function admitted(generation) {
  return publicationEvent('admit', { generation });
}
function snapshot(body, expected = publication.namespace, authenticating = false) {
  if (!browser('snapshot', { ...publication, expected_namespace: expected, incoming_namespace: body.namespace,
    incoming_sequence: body.sequence, authenticating })) return;
  world = body.program;
  publication = { ...publication, namespace: body.namespace, sequence: body.sequence };
  sourceFresh = true;
  dispatch({ type: 'snapshot', world });
}
function fatal(error) {
  const message = document.createElement('p');
  message.setAttribute('role', 'alert');
  message.textContent = error.message;
  surface.replaceChildren(message);
}
function dispatch(input) {
  if (disposed) return;
  const decision = interaction('step', { state, input, world, namespace: publication.namespace, now: BigInt(Math.floor(Date.now() / 1000)), display_lagged: !publicationEvent('ready') });
  state = decision.state;
  publication = publicationEvent('advance');
  render();
  for (const effect of decision.effects) execute(effect).catch(fatal);
  return decision.reply;
}
function render() {
  const scene = interaction('observe', { state, world, namespace: publication.namespace, now: BigInt(Math.floor(Date.now() / 1000)), display_lagged: !publicationEvent('ready') });
  const document = browser('render', { scene, viewport: physical.viewport().width,
    font_pixels: Math.ceil(parseFloat(getComputedStyle(globalThis.document.documentElement).fontSize)),
    system_dark: matchMedia('(prefers-color-scheme: dark)').matches });
  renderer.render(document, publication.semantic);
  publication = publicationEvent('document', { generation: publication.semantic });
  const generation = publication.semantic;
  renderer.whenCaughtUp().then(caughtUp => {
    if (!caughtUp || disposed) return;
    const lagged = !publicationEvent('ready');
    publication = publicationEvent('publish', { generation });
    if (lagged && publicationEvent('ready')) render();
  }).catch(fatal);
  reveal();
  motion.refresh();
  layoutReading();
}
function observedSelection(node, composing = false) {
  const encode = value => new TextEncoder().encode(value).length;
  return { start: encode(node.value.slice(0, node.selectionStart ?? node.value.length)),
    end: encode(node.value.slice(0, node.selectionEnd ?? node.value.length)), composing };
}
function editedAction(action, injection, value, raw = undefined, selection = undefined) {
  if (injection === 'input.value') return { ...action, input: { ...action.input, value } };
  if (injection === 'value') return { ...action, value,
    ...(raw === undefined ? {} : { raw }), ...(selection === undefined ? {} : { selection }) };
  throw new TypeError('Native field has no declared value injection');
}
function registerFiles(action, selected) {
  for (const file of selected) {
    const handle = crypto.randomUUID();
    files.set(handle, file);
    dispatch({ ...action, file: { handle, name: file.name, mime: file.type, bytes: file.size } });
  }
}
const renderer = new Renderer(surface, {
  resolveTarget(source) { return browser('resolve_target', source); },
  fieldSession(source) { return browser('field_session', source); },
  event(binding, event, key, node, generation) {
    if (!admitted(generation)) return;
    if (binding.kind === 'activate' || binding.kind === 'dismiss') { event.preventDefault(); sendAction(binding.action); }
    else if (binding.kind === 'submit') sendAction(binding.action);
    else if (binding.kind === 'edit') {
      let value = node.value;
      if (node.dataset.valueKind === 'json') {
        try { value = parseJson(node.value); }
        catch (error) {
          // DEFENSE: A user can pause while entering an incomplete JSON field; retain its raw invalid buffer.
          if (!(error instanceof SyntaxError)) throw error;
        }
      }
      dispatch(editedAction(binding.action, binding.injection, value, node.value, observedSelection(node, event.isComposing)));
    }
    else if (binding.kind === 'toggle') dispatch(editedAction(binding.action, binding.injection, node.checked));
    else if (binding.kind === 'files') registerFiles(binding.action,
      Array.from(event.clipboardData?.files ?? event.dataTransfer?.files ?? node.files ?? []));
  },
  key(event, key, node, record) {
    // DEFENSE: A handled keydown still bubbles through ancestor renderer records.
    if (event.defaultPrevented) return;
    if (!admitted(record.generation)) return;
    const bindings = record.metadata.meta?.key_actions;
    if (bindings) {
      const action = browser('key_action', { ...keyObservation(event), bindings });
      if (action !== null) { event.preventDefault(); sendAction(action); return; }
    }
    const form = node.form;
    if (form && (node.tagName === 'TEXTAREA' || node.tagName === 'INPUT')) {
      const submitter = form.querySelector('button[type="submit"],input[type="submit"]');
      editorKeyboard(event, observation => browser('key', { ...observation,
        multiline: node.tagName === 'TEXTAREA', enabled: !node.disabled && !submitter?.disabled, pending: false }), () => form.requestSubmit());
    }
    const dialog = node.closest('dialog[open],[aria-modal="true"]');
    if (dialog && event.key === 'Tab') {
      const targets = Array.from(dialog.querySelectorAll('button,a[href],input,textarea,select,[tabindex]')).filter(target =>
        target.tabIndex >= 0 && !target.matches(':disabled') && !target.closest('[inert],[hidden]') &&
        target.getClientRects().length && getComputedStyle(target).visibility !== 'hidden');
      const keys = targets.map((_, index) => String(index));
      const next = browser('focus_cycle', { current: String(targets.indexOf(event.target)), targets: keys, backward: event.shiftKey });
      if (next !== null) { event.preventDefault(); targets[Number(next)].focus(); }
    }
    if (node.dataset.readingRoot === 'true' && event.target.closest('[data-reading-root="true"]') === node) {
      const state = readings.get(key) ?? { intent: 'follow', anchor: null };
      readings.set(key, browser('reading', { state, event: 'key', keyboard: event.key,
        editable: event.target.matches('input,textarea,select') }).state);
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
    const state = readings.get(key) ?? { intent: 'follow', anchor: null };
    if (type === 'scroll' || type === 'pointer') {
      readings.set(key, browser('reading', { state, event: 'scroll' }).state);
    } else if (state.intent === 'history') {
      observeReadingAnchor(key, node, state);
    }
  },
  layout() {
    if (layoutFrame === null) layoutFrame = requestAnimationFrame(() => {
      layoutFrame = null; reveal(); layoutReading();
    });
  },
  codeSource(key, ordinal, text) {
    const identity = browser('code_key', { key, ordinal });
    let entry = codeBlocks.get(identity);
    if (!entry) {
      const decision = browser('code_initial', { key: identity, text });
      entry = { key: identity, state: decision.state, renderer: null };
      codeBlocks.set(identity, entry);
      renderCode(entry, decision);
    } else codeStep(entry, { type: 'source', value: text });
  },
  codeKey(key, ordinal) { return browser('code_key', { key, ordinal }); },
  fence(metadata, observed) {
    dispatch({ type: 'code_observed', origin: metadata.origin, document_key: metadata.document_key,
      epoch: metadata.epoch, revision: observed.inputRevision, ordinal: observed.ordinal,
      fence_kind: observed.kind, info_complete: observed.infoComplete,
      raw_info: observed.info, code_prefix: observed.code, closed: observed.closed,
      input_prefix: observed.inputPrefix });
  },
});

const physical = createPhysicalMeasurer({ surface, onChange: render });

function sendAction(action) {
  if (action.type === 'code') {
    const entry = codeBlocks.get(action.key);
    if (entry) codeStep(entry, action.input);
  } else dispatch(action);
}
function renderCode(entry, decision) {
  entry.state = decision.state;
  const target = renderer.target(`${entry.key}/toolbar`);
  if (target) {
    if (!entry.renderer || entry.renderer.root !== target) {
      entry.renderer?.dispose();
      entry.renderer = new Renderer(target, { event(binding, event) { event.preventDefault(); sendAction(binding.action); } });
    }
    entry.renderer.render(browser('render', { scene: decision.scene, viewport: Math.floor(surface.clientWidth),
      font_pixels: Math.ceil(parseFloat(getComputedStyle(globalThis.document.documentElement).fontSize)), system_dark: false }));
  }
  const code = renderer.target(`${entry.key}/code`);
  if (code) for (const { name, value } of decision.code_styles) code.style.setProperty(name, value);
  for (const effect of decision.effects) {
    if (effect.type === 'clipboard') {
      navigator.clipboard.writeText(effect.text).then(
        () => { if (codeBlocks.get(entry.key) === entry) codeStep(entry, { type: 'copied', ticket: effect.ticket, success: true }); },
        () => { if (codeBlocks.get(entry.key) === entry) codeStep(entry, { type: 'copied', ticket: effect.ticket, success: false }); });
    } else if (effect.type === 'expiry') {
      const timer = setTimeout(() => {
        timers.delete(timer);
        if (codeBlocks.get(entry.key) === entry) codeStep(entry, { type: 'expire', ticket: effect.ticket });
      }, Number(effect.milliseconds));
      timers.add(timer);
    }
  }
}
function codeStep(entry, input) { renderCode(entry, browser('code_step', { state: entry.state, input })); }

function observeReadingAnchor(key, node, state) {
  const viewport = node.getBoundingClientRect();
  const anchor = Array.from(node.querySelectorAll('[data-reading-anchor]')).find(target => target.getBoundingClientRect().bottom >= viewport.top);
  if (anchor) readings.set(key, browser('reading', { state, event: 'anchor', anchor: {
    key: anchor.dataset.key, offset: String(anchor.getBoundingClientRect().top - viewport.top) } }).state);
}
function readingStep(key, node, event) {
  const state = readings.get(key) ?? { intent: 'follow', anchor: null };
  const decision = browser('reading', { state, event });
  readings.set(key, decision.state);
  for (const effect of decision.effects) {
    if (effect.type === 'align_latest') node.scrollTop = node.scrollHeight;
    else if (effect.type === 'preserve_anchor') {
      const target = renderer.target(effect.anchor.key);
      if (target) node.scrollTop += target.getBoundingClientRect().top - node.getBoundingClientRect().top - Number(effect.anchor.offset);
    } else if (effect.type === 'measure_anchor') observeReadingAnchor(key, node, decision.state);
  }
}
function layoutReading() {
  for (const [key, record] of renderer.records) {
    if (record.node.dataset.readingRoot === 'true') readingStep(key, record.node, 'layout');
  }
}
function dismiss(event) {
  // DEFENSE: An inner menu can consume Escape before it reaches the enclosing dialog.
  if (event.defaultPrevented) return;
  const modal = renderer.modalRecord();
  const dismissal = modal?.events.find(binding => binding.kind === 'dismiss');
  if (!dismissal || !admitted(modal.generation)) return;
  if (event.type === 'keydown' && event.key === 'Escape' || event.type === 'pointerdown' && (!modal.node.contains(event.target) || event.target === modal.node && (() => {
    const box = modal.node.getBoundingClientRect();
    return event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom;
  })())) {
    event.preventDefault(); dispatch(dismissal.action);
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
    return reply.task_id;
  },
  field(editor) {
    return Array.from(renderer.records.values()).find(record => record.events.some(binding =>
      binding.action.editor && ticketKey(binding.action.editor) === ticketKey(editor)))?.node;
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
    await observeConnection({
      request: (url, signal) => request(url, { signal }),
      fetchEvents: (url, signal) => fetch(url, { signal, credentials: 'same-origin' }),
      signal: controller.signal,
      sequence: () => publication.sequence instanceof JsonNumber ? publication.sequence.source : publication.sequence,
      snapshot: body => snapshot(body, publication.namespace, !ready),
      ready() { ready = true; dispatch({ type: 'authenticated', ticket: effect.ticket, ok: true, value: null }); },
      notice(value) { dispatch({ type: 'stream', value }); return true; },
      current: () => !disposed && connection === controller && !controller.signal.aborted,
      namespace: () => publication.namespace,
      refreshNeeded(notice) {
        if (notice.sequence === undefined || typeof notice.namespace !== 'string') return true;
        return publicationEvent('refresh', { source_namespace: notice.namespace,
          source_sequence: notice.sequence, sources_fresh: sourceFresh });
      },
    });
  } catch (error) {
    // DEFENSE: Superseded fetches report AbortError after a newer connection owns the browser.
    if (controller.signal.aborted || connection !== controller) return;
    sourceFresh = false;
    const revoked = error.status === 401 || error.status === 403;
    dispatch(ready || revoked ? { type: 'disconnected', ticket: effect.ticket, error: error.message, revoked }
      : { type: 'authenticated', ticket: effect.ticket, ok: false, error: error.message });
  }
}
// Native drag events only observe the source and destination declared by Gallina.
// Capability admission, revision checks and command construction remain in CardPlaced.
let draggedCard = null;
surface.addEventListener('dragstart', event => {
  const node = event.target.closest?.('[data-card-id][draggable="true"]');
  if (!node || !surface.contains(node)) return;
  const record = renderer.records.get(`card/${node.dataset.cardId}`);
  if (record?.node !== node || !admitted(record.generation)) return;
  draggedCard = { card_id: new JsonNumber(node.dataset.cardId),
    revision: new JsonNumber(node.dataset.cardRevision),
    observed_at: new JsonNumber(node.dataset.cardObservedAt), generation: record.generation };
  event.dataTransfer.setData('application/x-selvedge-card', node.dataset.cardId);
  event.dataTransfer.effectAllowed = 'move';
});
surface.addEventListener('dragover', event => {
  if (!draggedCard || !admitted(draggedCard.generation)) return;
  const target = event.target.closest?.('[data-drop-status]');
  if (target && surface.contains(target)) { event.preventDefault(); event.dataTransfer.dropEffect = 'move'; }
});
surface.addEventListener('drop', event => {
  const source = draggedCard;
  draggedCard = null;
  if (!source || !admitted(source.generation)) return;
  const target = event.target.closest?.('[data-drop-status]');
  if (!target || !surface.contains(target)) return;
  event.preventDefault();
  const { generation, ...captured } = source;
  dispatch({ type: 'card_placed', ...captured, status: target.dataset.dropStatus,
    before_card: target.dataset.cardBefore ? new JsonNumber(target.dataset.cardBefore) : null });
});
surface.addEventListener('dragend', () => { draggedCard = null; });

async function settled(type, ticket, work) {
  try { dispatch({ type, ticket, ok: true, value: await work() }); }
  catch (error) {
    // DEFENSE: Network and browser resource operations fail through their matching completion ticket.
    dispatch({ type, ticket, ok: false, error: error.message });
  }
}
async function assessCommand(effect) {
  const key = ticketKey(effect.request.editor);
  assessments.get(key)?.abort();
  const controller = new AbortController();
  assessments.set(key, controller);
  try {
    const value = await post('/api/assess', effect.request, controller.signal);
    dispatch({ type: 'command_assessed', ticket: effect.ticket, ok: true, value });
  } catch (error) {
    // DEFENSE: A newer draft assessment or page teardown cancels this superseded request.
    if (controller.signal.aborted) return;
    dispatch({ type: 'command_assessed', ticket: effect.ticket, ok: false, error: error.message });
  } finally {
    if (assessments.get(key) === controller) assessments.delete(key);
  }
}
async function execute(effect) {
  switch (effect.type) {
    case 'authenticate': return authenticate(effect);
    case 'schedule_reconnect': {
      const timer = setTimeout(() => { timers.delete(timer); dispatch({ type: 'retry_connection', ticket: effect.ticket }); }, Number(effect.milliseconds));
      timers.add(timer); return;
    }
    case 'command': return settled('completed', effect.ticket, () => requestCommand(effect.command));
    case 'assess_command': return assessCommand(effect);
    case 'save_appearance':
      try { localStorage.setItem('selvedge-appearance', effect.value); }
      // DEFENSE: Browser privacy settings or storage quotas can reject a local preference write.
      catch (error) { dispatch({ type: 'storage_problem', message: `无法保存外观设置：${error.message}` }); }
      return;
    case 'persist_model_preference':
      try { localStorage.setItem('selvedge-model-preference', stringifyJson({ profile: effect.profile, reasoning: effect.reasoning })); }
      // DEFENSE: A rejected preference write must not undo the already accepted model choice.
      catch (error) { dispatch({ type: 'storage_problem', message: `无法保存模型偏好：${error.message}` }); }
      return;
    case 'upload': {
      const controller = new AbortController(); transfers.set(ticketKey(effect.ticket), controller);
      const file = files.get(effect.file.handle);
      await settled('uploaded', effect.ticket, async () => {
        const body = await request(`/api/board/attachments?name=${encodeURIComponent(file.name)}`,
          { method: 'POST', body: file, signal: controller.signal });
        files.delete(effect.file.handle); return body.result;
      });
      transfers.delete(ticketKey(effect.ticket)); return;
    }
    case 'abort_upload': transfers.get(ticketKey(effect.ticket))?.abort(); return;
    case 'skill_catalog': {
      try {
        const body = await post('/api/browser/observation', taskObservation(effect, { kind: 'skill-catalog', workspace: effect.workspace }));
        if (body.ok) dispatch({ type: 'skill_catalog', editor: effect.editor, ticket: effect.ticket, skills: body.skills });
        else dispatch({ type: 'skill_catalog_failed', editor: effect.editor, ticket: effect.ticket, error: body.error });
      } catch (error) {
        // DEFENSE: A workspace catalog observation may fail or change after its requested editor is closed.
        dispatch({ type: 'skill_catalog_failed', editor: effect.editor, ticket: effect.ticket, error: error.message });
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
      const body = await post('/api/browser/observation', taskObservation(effect, { kind: 'browse-directories', path: effect.path }));
      if (body.ok === false) throw new Error(body.error);
      return body;
    });
    case 'preview': return settled('previewed', effect.ticket, async () => {
      const response = await fetch(`/api/board/attachments/${encodeURIComponent(effect.file.id)}`, { credentials: 'same-origin' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const url = URL.createObjectURL(await response.blob()); resources.add(url); return url;
    });
    case 'release_preview': URL.revokeObjectURL(effect.url); resources.delete(effect.url); return;
    case 'download': {
      const response = await fetch(`/api/board/attachments/${encodeURIComponent(effect.file.id)}`, { credentials: 'same-origin' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const url = URL.createObjectURL(await response.blob());
      const link = document.createElement('a'); link.href = url; link.download = effect.file.name;
      link.click(); setTimeout(() => URL.revokeObjectURL(url), 0); return;
    }
    case 'focus': {
      const generation = publication.semantic;
      const target = () => renderer.resolveTarget(effect.key, { fallback: effect.fallback });
      if (!target()) await renderer.whenCaughtUp();
      if (admitted(generation)) target()?.focus({ preventScroll: true });
      return;
    }
    case 'follow_latest': {
      const node = renderer.resolveTarget(effect.key, { modal: false });
      if (node) readingStep(node.dataset.key, node, 'follow');
      return;
    }
    case 'scroll_to_message': {
      const target = renderer.resolveTarget(effect.key, { modal: false });
      if (target) {
        const root = target.closest('[data-reading-root="true"]');
        if (root) {
          const state = readings.get(root.dataset.key) ?? { intent: 'follow', anchor: null };
          readings.set(root.dataset.key, browser('reading', { state, event: 'locate', index: effect.message_index }).state);
        }
        target.scrollIntoView({ block: 'start', behavior: 'instant' });
      }
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
        dispatch({ type: 'interactive', input: { type: 'continue', owner: effect.owner } });
      }, 0); timers.add(timer); return;
    }
    case 'interactive_load': {
      let saved;
      try { saved = storage.load(effect.storage_key); }
      catch (error) {
        // DEFENSE: Browser storage can be unavailable; preserve the entry and report the failed observation.
        dispatch({ type: 'interactive', input: { type: 'storage', owner: effect.owner,
          revision: effect.revision, ok: false, message: error.message } }); return;
      }
      dispatch({ type: 'interactive', input: { type: 'restore', owner: effect.owner,
        definition: effect.definition, revision: effect.revision,
        present: saved.present, payload: saved.value, settled: true } }); return;
    }
    case 'interactive_save': storage.save(effect.storage_key, effect.payload, (ok, message) =>
      dispatch({ type: 'interactive', input: { type: 'storage', owner: effect.owner, revision: effect.revision, ok, message } })); return;
    case 'interactive_remove': storage.remove(effect.storage_key); return;
    case 'interactive_clipboard': {
      let ok = true, message = '';
      try { await navigator.clipboard.writeText(effect.text); }
      catch (error) {
        // DEFENSE: Clipboard permission and browser activation requirements can reject a declared copy effect.
        ok = false; message = error.message;
      }
      dispatch({ type: 'interactive', input: { type: 'feedback', owner: effect.owner,
        path: effect.path, ticket: effect.ticket, ok, message } }); return;
    }
    case 'interactive_open_url': {
      const url = safeHref(effect.url);
      if (url !== null) window.open(url, '_blank', 'noopener,noreferrer');
      dispatch({ type: 'interactive', input: { type: 'feedback', owner: effect.owner,
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
  const binding = record?.events.find(binding => binding.kind === 'edit' && binding.action.editor);
  if (!binding) return;
  const selection = observedSelection(node, renderer.composing.has(node));
  const observed = stringifyJson(selection);
  if (selections.get(node) === observed) return;
  selections.set(node, observed);
  dispatch({ type: 'skill_selection', editor: binding.action.editor, selection });
}
document.addEventListener('selectionchange', selectionChanged);

window.addEventListener('pagehide', () => {
  disposed = true; document.removeEventListener('selectionchange', selectionChanged); document.removeEventListener('keydown', dismiss); document.removeEventListener('pointerdown', dismiss); connection?.abort(); audio.dispose(); motion.dispose(); physical.dispose(); renderer.dispose(); storage.flush();
  for (const timer of timers) clearTimeout(timer);
  for (const entry of codeBlocks.values()) entry.renderer?.dispose();
  for (const controller of transfers.values()) controller.abort();
  for (const controller of assessments.values()) controller.abort();
  for (const resource of resources) URL.revokeObjectURL(resource);
  if (layoutFrame !== null) cancelAnimationFrame(layoutFrame);
}, { once: true });
window.addEventListener('focus', () => audio.focus());
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', render);
render();
try {
  const restoredAppearance = localStorage.getItem('selvedge-appearance');
  if (restoredAppearance !== null) dispatch({ type: 'appearance_restored', value: restoredAppearance });
  const restoredModel = localStorage.getItem('selvedge-model-preference');
  if (restoredModel !== null) dispatch({ type: 'model_preference_restored', value: restoredModel });
}
// DEFENSE: Storage access can be disabled while the authenticated task service remains available.
catch (error) { dispatch({ type: 'storage_problem', message: `无法读取本地设置：${error.message}` }); }
dispatch({ type: 'connect' });
