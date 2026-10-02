import * as Bend from './generated/browser-model.mjs';
import { decodeBendValue, encodeBendValue } from './bend-value.mjs';
import { Renderer, list } from './renderer.mjs';
import { EventFrames } from './events.mjs';

const value = ($, fields = {}) => ({ $, ...fields });
const bool = enabled => Boolean(enabled);
const linked = items => items.reduceRight((tail, head) => value('Con', { head, tail }), value('Nil'));
function json(input) {
  if (input === null) return value('Null');
  if (typeof input === 'boolean') return value('Boolean', { value: bool(input) });
  if (typeof input === 'number') return value('Number', { lexeme: String(input) });
  if (typeof input === 'string') return value('Text', { value: input });
  if (Array.isArray(input)) return value('Array', { items: linked(input.map(json)) });
  return value('Object', { fields: linked(Object.entries(input).map(([name, item]) => value('Field', { name, value: json(item) }))) });
}
function showJson(input) {
  switch (input.$) {
    case 'Null': return 'null';
    case 'Boolean': return input.value ? 'true' : 'false';
    case 'Number': return input.lexeme;
    case 'Text': return JSON.stringify(input.value);
    case 'Array': return `[${list(input.items).map(showJson).join(',')}]`;
    case 'Object': return `{${list(input.fields).map(field => `${JSON.stringify(field.name)}:${showJson(field.value)}`).join(',')}}`;
    default: throw new TypeError('Expected Bend JSON');
  }
}
const root = document.getElementById('surface');
let state = Bend.initial(Bend.empty(), 0n);
let token = sessionStorage.getItem('selvedge-token') ?? '';
let connection;
let revision = 0;
let dragged = null;
let renderQueued = false;
const files = new Map();
const transfers = new Map();
const resources = new Set();
const streams = new Map();
const renderer = new Renderer(root, {
  event(binding, event, node, composing) {
    switch (binding.$) {
      case 'Activate': event.preventDefault(); commit(Bend.activate(binding.key, state)); break;
      case 'EditText': commit(Bend.edit_text(binding.key, node.value, state)); break;
      case 'ConfirmText': commit(Bend.confirm_text(binding.key, event.key, bool(event.isComposing || composing || event.keyCode === 229), bool(event.ctrlKey), bool(event.altKey), bool(event.shiftKey), bool(event.metaKey), state)); break;
      case 'EditToggle': commit(Bend.edit_toggle(binding.key, bool(node.checked), state)); break;
      case 'SelectFiles':
        for (const file of node.files ?? []) {
          const handle = crypto.randomUUID(); files.set(handle, file);
          commit(Bend.attach(binding.key, value('File', { handle, name: file.name, mime: file.type, bytes: file.size }), state));
        }
        node.value = ''; break;
      case 'DragCard': dragged = binding.key; event.dataTransfer?.setData('text/plain', binding.key); break;
      case 'DropCard': if (dragged) commit(Bend.place(dragged, binding.key, state)); dragged = null; break;
      case 'PlaceCard': event.preventDefault(); commit(Bend.place(binding.key, binding.target, state)); break;
      default: throw new TypeError(`Unknown document event ${binding.$}`);
    }
  },
  codeKey: (source, ordinal) => Bend.code_key(source, ordinal),
  codeSource(source, ordinal, text) { queueMicrotask(() => commit(Bend.code_source(source, ordinal, text, state))); },
  changed() {
    if (!renderQueued) { renderQueued = true; queueMicrotask(() => { renderQueued = false; render(); }); }
  },
});
function render() { renderer.render(Bend.observe(state)); }
function commit(decision) {
  state = decision.state; render();
  for (const effect of list(decision.effects)) Promise.resolve(execute(effect)).catch(error => console.error(error));
}
function step(input) { commit(Bend.step(input, state)); }
function native(input) { step(value('Native', { input })); }
function platform(input) { native(value('PlatformInput', { input })); }
function product(input) { platform(value('ProductInput', { input })); }
async function request(url, options = {}, credential = token) {
  const response = await fetch(url, { ...options, headers: { authorization: `Bearer ${credential}`, ...options.headers } });
  const body = await response.json();
  if (!response.ok) { const error = new Error(body.error?.message ?? body.error ?? `HTTP ${response.status}`); error.body = body; throw error; }
  return body;
}
function snapshot(body) {
  revision = Math.max(revision, body.sequence);
  step(value('Snapshot', { sequence: BigInt(body.sequence), program: decodeBendValue(body.program) }));
}
async function refresh() { snapshot(await request('/api/browser/state')); }
function post(url, body) { return request(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body }); }
function result(ok, payload) { return ok ? value('Done', { value: payload }) : value('Fail', { error: payload }); }
async function execute(effect) {
  switch (effect.$) {
    case 'Command': {
      try {
        const body = await post('/api/browser/command', `{"command":${showJson(effect.command)}}`);
        revision = Math.max(revision, body.sequence);
        step(value('Completed', { ticket: effect.ticket, sequence: BigInt(body.sequence), program: decodeBendValue(body.program), reply: json(body.reply) }));
      } catch (error) {
        if (error.body?.error?.code === 'command_not_submitted') {
          commit(Bend.command_rejected(effect.ticket, error.body.error.message, state));
        } else if (error.body?.program && error.body?.reply) {
          const body = error.body;
          step(value('Completed', { ticket: effect.ticket, sequence: BigInt(body.sequence), program: decodeBendValue(body.program), reply: json(body.reply) }));
        } else step(value('Failed', { ticket: effect.ticket, error: error.message }));
      }
      break;
    }
    case 'Service': await service(effect.effect); break;
    case 'Directories': {
      const workspace = { roots: list(effect.workspace.roots), primary_root: effect.workspace.primary.$ === 'Some' ? effect.workspace.primary.value : null };
      try { commit(Bend.directories_completed(effect.ticket, bool(true), json(await post('/api/browser/observation', JSON.stringify({ kind: 'directories', workspace }))), state)); }
      catch (error) { commit(Bend.directories_completed(effect.ticket, bool(false), json({ error: error.message }), state)); }
      break;
    }
    case 'BrowserEffect': await browserEffect(effect.effect); break;
    case 'RenderingFailed': console.error('Bend browser failure', JSON.stringify(encodeBendValue(effect))); break;
    default: throw new TypeError(`Unknown browser effect ${effect.$}`);
  }
}
async function service(effect) {
  switch (effect.$) {
    case 'Authenticate': {
      try {
        const body = await request('/api/browser/state', {}, effect.credential);
        token = effect.credential; sessionStorage.setItem('selvedge-token', token);
        snapshot(body); product(value('Authenticated', { ticket: effect.ticket, result: result(true, value('Unit')) }));
        connection?.abort(); connection = new AbortController();
        void observeStreams().catch(error => console.error('Stream observation failed', error));
        void watch(connection.signal, token);
      } catch (error) { product(value('Authenticated', { ticket: effect.ticket, result: result(false, error.message) })); }
      break;
    }
    case 'StoreAppearance': {
      const appearance = effect.appearance.$;
      localStorage.setItem('selvedge-appearance', appearance);
      document.documentElement.style.colorScheme = appearance === 'DarkAppearance' ? 'dark' : appearance === 'LightAppearance' ? 'light' : 'light dark';
      break;
    }
    case 'Upload': {
      const controller = new AbortController(); transfers.set(effect.ticket, controller);
      try {
        const file = files.get(effect.file.handle);
        if (!file) throw new Error('Selected file handle is unavailable');
        const body = await request(`/api/board/attachments?name=${encodeURIComponent(file.name)}`, { method: 'POST', body: file, signal: controller.signal });
        product(value('Uploaded', { ticket: effect.ticket, result: result(true, value('Attachment', body.result)) }));
        files.delete(effect.file.handle);
      } catch (error) { product(value('Uploaded', { ticket: effect.ticket, result: result(false, error.message) })); }
      finally { transfers.delete(effect.ticket); }
      break;
    }
    case 'CancelTransfer': transfers.get(effect.ticket)?.abort(); transfers.delete(effect.ticket); break;
    case 'ReadDirectories': {
      try {
        const body = await post('/api/browser/observation', JSON.stringify({ kind: 'browse-directories', path: effect.path }));
        commit(Bend.directory_listed(effect.ticket, bool(true), json(body), state));
      } catch (error) {
        commit(Bend.directory_listed(effect.ticket, bool(false), json({ error: error.message }), state));
      }
      break;
    }
    case 'ReadAttachment': {
      try {
        const response = await fetch(`/api/board/attachments/${encodeURIComponent(effect.file.id)}`, { headers: { authorization: `Bearer ${token}` } });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const resource = URL.createObjectURL(await response.blob()); resources.add(resource);
        product(value('AttachmentRead', { ticket: effect.ticket, result: result(true, resource) }));
      } catch (error) { product(value('AttachmentRead', { ticket: effect.ticket, result: result(false, error.message) })); }
      break;
    }
    case 'DownloadAttachment': {
      const response = await fetch(`/api/board/attachments/${encodeURIComponent(effect.file.id)}`, { headers: { authorization: `Bearer ${token}` } });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const url = URL.createObjectURL(await response.blob());
      const link = document.createElement('a'); link.href = url; link.download = effect.file.name; link.click(); setTimeout(() => URL.revokeObjectURL(url), 0); break;
    }
    default: throw new TypeError(`Unknown client service effect ${effect.$}`);
  }
}
const rect = node => { const r = node.getBoundingClientRect(); return value('Rect', { left: r.left, top: r.top, right: r.right, bottom: r.bottom }); };
const owner = node => node?.closest?.('[data-native-key]')?.getAttribute('data-native-key') ?? '';
const hasArea = bounds => bounds.right > bounds.left && bounds.bottom > bounds.top;
function frameGeometry(node, bounds) {
  let painted = hasArea(bounds);
  if (node.checkVisibility) painted &&= node.checkVisibility({ opacityProperty: true, visibilityProperty: true, contentVisibilityAuto: true });
  const intersection = { left: Math.max(0, bounds.left), top: Math.max(0, bounds.top), right: Math.min(innerWidth, bounds.right), bottom: Math.min(innerHeight, bounds.bottom) };
  let scrollable = false;
  for (let ancestor = node; ancestor; ancestor = ancestor.parentElement) {
    const style = getComputedStyle(ancestor);
    if (ancestor.hidden || style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse' || style.contentVisibility === 'hidden' || Number(style.opacity) === 0) painted = false;
    if (ancestor === node) continue;
    const clip = ancestor.getBoundingClientRect();
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
  return { visible, scrollReachable: painted && control && scrollable,
    hitOwner: visible ? owner(document.elementFromPoint((intersection.left + intersection.right) / 2, (intersection.top + intersection.bottom) / 2)) : '' };
}
function frame() {
  const nodes = [...root.querySelectorAll('[data-native-key]')];
  const elements = nodes.map(node => {
    const bounds = rect(node); const geometry = frameGeometry(node, bounds);
    const enabled = !node.disabled && !node.closest('[inert]') && node.getAttribute('aria-disabled') !== 'true';
    const tab = enabled && node.tabIndex >= 0;
    return value('Element', { key: owner(node), visible: bool(geometry.visible), enabled: bool(enabled), tab_stop: bool(tab), keyboard_reachable: bool(tab), scroll_reachable: bool(geometry.scrollReachable), bounds,
      center_hit_owner: geometry.hitOwner });
  });
  const focused = owner(document.activeElement);
  const tabOrder = nodes.filter(node => {
    if (node.tabIndex < 0 || node.disabled || node.closest('[inert],[hidden]')) return false;
    const geometry = frameGeometry(node, rect(node));
    return geometry.visible || geometry.scrollReachable;
  });
  tabOrder.sort((a, b) => (a.tabIndex > 0 ? a.tabIndex : Infinity) - (b.tabIndex > 0 ? b.tabIndex : Infinity));
  return value('Frame', { viewport: value('Rect', { left: 0, top: 0, right: innerWidth, bottom: innerHeight }), elements: linked(elements),
    focused: focused ? value('Some', { value: focused }) : value('None'), tab_order: linked(tabOrder.map(owner)) });
}
async function browserEffect(effect) {
  if (effect.$ === 'MeasureFrame') {
    requestAnimationFrame(() => {
      if (root.firstElementChild?.getAttribute('data-frame-observation') !== 'off') native(value('FrameObserved', { generation: effect.generation, frame: frame() }));
    }); return;
  }
  if (effect.$ !== 'PlatformEffect') throw new TypeError(`Unknown web effect ${effect.$}`);
  const physical = effect.effect;
  switch (physical.$) {
    case 'Focus': {
      if (physical.ticket !== state.web.application.platform.focus_ticket) return;
      const node = renderer.target(physical.target); if (!node) return;
      node.focus({ preventScroll: true });
      platform(value('FocusApplied', { ticket: physical.ticket, identity: owner(document.activeElement) })); break;
    }
    case 'Clipboard': {
      let success = false;
      try { await navigator.clipboard.writeText(physical.effect.text); success = true; } catch { /* Completion preserves failure. */ }
      product(value('ClipboardCompleted', { identity: physical.block, ticket: physical.effect.ticket, success: bool(success) }));
      setTimeout(() => product(value('ClipboardFeedbackExpired', { identity: physical.block })), 1800); break;
    }
    case 'Scroll': applyReading(physical); break;
    default: throw new TypeError(`Unknown platform effect ${physical.$}`);
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
  return node ? value('Anchor', { identity: node.dataset.readingKey, offset: node.getBoundingClientRect().top - viewport.top }) : null;
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
function measureUserAnchor(surface) {
  const pending = readingMeasurements.get(surface);
  if (!pending || pending.frame !== null) return;
  pending.frame = requestAnimationFrame(() => {
    pending.frame = null;
    if (!surface.isConnected) { readingMeasurements.delete(surface); return; }
    const observed = anchor(surface);
    if (pending.pointers.size === 0) readingMeasurements.delete(surface);
    if (observed) readingInput(surface, value('AnchorObserved', { anchor: observed }));
  });
}
function beginUserScroll(surface, pointerId) {
  readingUserOwned.add(surface);
  let pending = readingMeasurements.get(surface);
  if (!pending) { pending = { frame: null, pointers: new Set() }; readingMeasurements.set(surface, pending); }
  if (pointerId !== undefined) { pending.pointers.add(pointerId); readingPointers.set(pointerId, surface); }
  readingInput(surface, value('BeginUserScroll'));
  measureUserAnchor(surface);
}
function applyReading(physical) {
  const surface = readingSurface(physical.task, physical.generation); if (!surface) return;
  const effect = physical.effect;
  switch (effect.$) {
    case 'LeaveViewport':
      markReadingCorrection(surface);
      // An instant move to the current offset cancels an earlier smooth correction.
      surface.scrollTo({ top: surface.scrollTop, left: surface.scrollLeft, behavior: 'instant' }); break;
    case 'AlignLatest':
      if (!readingMeasurements.has(surface)) {
        readingUserOwned.delete(surface); markReadingCorrection(surface);
        surface.scrollTo({ top: surface.scrollHeight, behavior: effect.animate ? 'smooth' : 'instant' });
      }
      break;
    case 'PreserveAnchor': {
      if (readingMeasurements.has(surface)) break;
      const node = [...surface.querySelectorAll('[data-reading-key]')].find(item => item.dataset.readingKey === effect.anchor.identity);
      if (node) { markReadingCorrection(surface); surface.scrollTop += node.getBoundingClientRect().top - surface.getBoundingClientRect().top - effect.anchor.offset; } break;
    }
    case 'MeasureAnchor': {
      if (readingMeasurements.has(surface)) { measureUserAnchor(surface); break; }
      const observed = anchor(surface); if (observed) readingInput(surface, value('AnchorObserved', { anchor: observed })); break;
    }
    case 'ReserveComposer': { const content = root.querySelector(`[data-reading-content][data-reading-task="${physical.task}"]`); if (content) content.style.paddingBottom = `${effect.height}px`; break; }
    default: throw new TypeError(`Unknown reading effect ${effect.$}`);
  }
}
function streamFacts() {
  const facts = [...streams.values()].map(entry => ({ task_id: entry.task, ticket: entry.ticket,
    parts: [...entry.parts].map(([output_index, text]) => ({ output_index, text })) }));
  commit(Bend.streams(json({ kind: 'streams', streams: facts }), state));
}
function streamNotice(notice) {
  if (!Number.isSafeInteger(notice.task_id) || !Number.isSafeInteger(notice.ticket)) return;
  const key = `${notice.task_id}:${notice.ticket}`;
  if (notice.type === 'stream_start') { streams.set(key, { task: notice.task_id, ticket: notice.ticket, parts: new Map() }); streamFacts(); return; }
  if (notice.type === 'stream_end' || notice.type === 'stream_cancel') { streams.delete(key); streamFacts(); return; }
  const parts = streams.get(key)?.parts;
  if (!parts || !['delta', 'snapshot'].includes(notice.type) || typeof notice.text !== 'string' || !Number.isSafeInteger(notice.output_index)) return;
  const text = notice.type === 'delta' ? (parts.get(notice.output_index) ?? '') + notice.text : notice.text;
  if (text.length > 4 * 1024 * 1024 || parts.size >= 32 && !parts.has(notice.output_index)) return;
  parts.set(notice.output_index, text); streamFacts();
}
async function observeStreams() {
  const body = await post('/api/browser/observation', JSON.stringify({ kind: 'streams' }));
  streams.clear();
  for (const entry of body.streams) streams.set(`${entry.task_id}:${entry.ticket}`, { task: entry.task_id, ticket: entry.ticket, parts: new Map(entry.parts.map(part => [part.output_index, part.text])) });
  commit(Bend.streams(json(body), state));
}
async function watch(signal, credential) {
  while (!signal.aborted) {
    try {
      const response = await fetch(`/api/events?after=${revision}`, { headers: { authorization: `Bearer ${credential}` }, signal });
      if (!response.ok || !response.body) throw new Error(`Event connection: HTTP ${response.status}`);
      const reader = response.body.getReader(); const decoder = new TextDecoder();
      const frames = new EventFrames(notice => {
        if (signal.aborted) return;
        if (notice.type === 'commit') { revision = Math.max(revision, notice.sequence); void refresh().catch(error => product(value('Disconnected', { reason: error.message }))); }
        else if (notice.type === 'fatal') throw new Error(notice.message);
        else streamNotice(notice);
      });
      for (;;) { const { done, value: chunk } = await reader.read(); if (done) break; frames.write(decoder.decode(chunk, { stream: true })); }
      throw new Error('Event connection ended');
    } catch (error) {
      if (signal.aborted) return;
      product(value('Disconnected', { reason: error.message }));
      streams.clear(); streamFacts();
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
}
function environment() {
  native(value('EnvironmentObserved', { environment: value('Environment', { viewport: value('Viewport', { width: BigInt(innerWidth), height: BigInt(innerHeight) }), system_dark: bool(matchMedia('(prefers-color-scheme: dark)').matches) }) }));
}
window.addEventListener('resize', environment);
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', environment);
const motion = matchMedia('(prefers-reduced-motion: reduce)');
motion.addEventListener('change', () => platform(value('MotionPreference', { reduced: bool(motion.matches) })));
root.addEventListener('focusin', () => platform(value('FocusObserved', { identity: owner(document.activeElement) })));
window.addEventListener('pagehide', () => { connection?.abort(); for (const resource of resources) URL.revokeObjectURL(resource); });
const bootEffects = [];
for (const input of [
  value('EnvironmentObserved', { environment: value('Environment', { viewport: value('Viewport', { width: BigInt(innerWidth), height: BigInt(innerHeight) }), system_dark: bool(matchMedia('(prefers-color-scheme: dark)').matches) }) }),
  value('PlatformInput', { input: value('MotionPreference', { reduced: bool(motion.matches) }) }),
]) {
  const decision = Bend.step(value('Native', { input }), state);
  state = decision.state; bootEffects.push(...list(decision.effects));
}
render();
for (const effect of bootEffects) Promise.resolve(execute(effect)).catch(error => console.error(error));
native(value('Mount'));
const hash = new URLSearchParams(location.hash.slice(1));
if (hash.has('token')) { token = hash.get('token'); history.replaceState(null, '', location.pathname + location.search); }
if (token) commit(Bend.connect(token, state));

function editorEvent(node, event) {
  const key = node?.getAttribute?.('data-native-editor-key');
  if (key) commit(Bend.editor_event(key, event, state));
}
root.addEventListener('compositionstart', event => editorEvent(event.target, value('CompositionChanged', { composing: bool(true) })));
root.addEventListener('compositionend', event => editorEvent(event.target, value('CompositionChanged', { composing: bool(false) })));
root.addEventListener('keydown', event => {
  if (event.key === 'Tab' || event.key === 'Escape') {
    const result = Bend.key_event(event.key, bool(event.shiftKey), state);
    if (result.handled) event.preventDefault();
    commit(result.decision);
    return;
  }
  if (event.key === 'Enter' && event.target.hasAttribute('data-native-editor-key')) {
    if (!event.isComposing && !event.shiftKey && !event.altKey) event.preventDefault();
    editorEvent(event.target, value('Enter', { shift: bool(event.shiftKey), alt: bool(event.altKey), modified: bool(event.ctrlKey || event.metaKey) }));
  }
});
root.addEventListener('select', event => {
  const node = event.target;
  if (typeof node.selectionStart === 'number') editorEvent(node, value('SelectionChanged', { selection: value('Selection', {
    start: BigInt(node.selectionStart), end: BigInt(node.selectionEnd), direction: node.selectionDirection ?? 'none',
  }) }));
}, true);
let layoutFrame = null;
function observeReadingLayout() {
  if (layoutFrame !== null) return;
  layoutFrame = requestAnimationFrame(() => {
    layoutFrame = null;
    for (const surface of root.querySelectorAll('[data-reading-scroll]')) {
      const dock = root.querySelector(`[data-reading-dock][data-reading-task="${surface.dataset.readingTask}"]`);
      const dockExtent = dock ? Math.max(0, surface.getBoundingClientRect().bottom - dock.getBoundingClientRect().top) : 0;
      const signature = `${dockExtent}:${surface.clientHeight}`;
      if (surface.dataset.observedLayout === signature) continue;
      surface.dataset.observedLayout = signature;
      readingInput(surface, value('LayoutChanged', { dock_extent: dockExtent, viewport_height: surface.clientHeight }));
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
  const scope = state.web.application.platform.scope;
  const layerKey = Bend.active_layer_key(state);
  const layer = scope.$ === 'Temporary' && layerKey.$ === 'Some'
    ? [...root.querySelectorAll('[data-layer-key]')].find(node => node.dataset.layerKey === layerKey.value)
    : null;
  if (layer?.dataset.layerOutside === 'true') {
    const path = event.composedPath();
    const onTrigger = path.some(node => {
      const key = node?.getAttribute?.('data-native-key');
      return key && (key === scope.restore || key.endsWith(`/${scope.restore}`));
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
  const borderLeft = Number.parseFloat(style.borderLeftWidth) || 0;
  const borderRight = Number.parseFloat(style.borderRightWidth) || 0;
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
  const pending = readingMeasurements.get(surface);
  if (pending) { pending.pointers.delete(event.pointerId); measureUserAnchor(surface); }
}
window.addEventListener('pointerup', endReadingPointer, true);
window.addEventListener('pointercancel', endReadingPointer, true);
root.addEventListener('scroll', event => {
  const surface = event.target;
  if (!surface.matches?.('[data-reading-scroll]')) return;
  if (!readingMeasurements.has(surface) && readingUserOwned.has(surface) && !readingCorrections.has(surface)) {
    readingMeasurements.set(surface, { frame: null, pointers: new Set() });
  }
  if (readingMeasurements.has(surface)) measureUserAnchor(surface);
}, true);
for (const node of root.querySelectorAll('[data-reading-scroll],[data-reading-content],[data-reading-dock]')) { observed.add(node); resizeObserver.observe(node); }
observeReadingLayout();
