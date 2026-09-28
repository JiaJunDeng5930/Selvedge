import { mount } from './renderer.mjs';
import { Streams } from './streams.mjs';
import { EventFrames, acknowledgeDrafts } from './events.mjs';

const $ = id => document.getElementById(id);
const stored = key => { try { return sessionStorage.getItem(key); } catch { return null; } };
const store = (key, value) => { try { sessionStorage.setItem(key, value); } catch { /* Private browsing can forbid persistence. */ } };
let token = new URLSearchParams(location.hash.slice(1)).get('token') || stored('selvedge-token') || '';
if (location.hash) history.replaceState(null, '', location.pathname);
let state = null;
let revision = 0;
let requests = Promise.resolve();
let refreshState = { queued: false, again: false };
let connection;
let generation = 0;
let surface;
let liveFollow = true;
const streams = new Streams();
const drafts = new Map();
const disclosures = new Map();

function report(message = '') { $('error').textContent = message; $('error').hidden = !message; }
function status(text, state) { $('connection').textContent = text; $('connection').dataset.status = state; }

async function api(body, signal, credential) {
  const response = await fetch('/api/ui', { method: 'POST', signal,
    headers: { authorization: `Bearer ${credential}`, 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const value = await response.json();
  if (!response.ok || !value.ok) {
    const error = new Error(value.error?.message ?? `HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }
  return value;
}

async function attachmentRequest(url, options = {}) {
  const epoch = generation;
  const response = await fetch(url, { ...options, signal: connection?.signal,
    headers: { authorization: `Bearer ${token}` } });
  if (epoch !== generation) { await response.body?.cancel(); throw new Error('The workspace connection changed'); }
  if (!response.ok) {
    const value = await response.json().catch(() => null);
    throw new Error(value?.error?.message ?? `HTTP ${response.status}`);
  }
  return response;
}

async function uploadAttachment(file) {
  const response = await attachmentRequest(`/api/board/attachments?name=${encodeURIComponent(file.name)}`, { method: 'POST', body: file });
  return (await response.json()).result;
}

async function readAttachment(id) {
  return (await attachmentRequest(`/api/board/attachments/${encodeURIComponent(id)}`)).blob();
}

// The cursor is opaque. All command binding, visibility and enabled decisions
// come from the native presentation; this queue owns only browser interactions.
function dispatch(event, formKey, submitted, retainedFields) {
  const epoch = generation;
  const signal = connection?.signal;
  const credential = token;
  const next = requests.then(async () => {
    if (epoch !== generation) return;
    const value = await api({ state, event }, signal, credential);
    if (epoch !== generation) return;
    const result = value.result;
    revision = Math.max(revision, value.sequence);
    state = result.presentation.state;
    if (formKey && result.receipt.ok) acknowledgeDrafts(drafts, formKey, submitted,
      typeof retainedFields === 'function' ? retainedFields() : retainedFields);
    const previousSelection = surface?.selected;
    surface = mount($('surface'), result.presentation.root, dispatch, {
      drafts, disclosures, uploadAttachment, readAttachment,
      takeMarkdown: (text, selected) => streams.take(text, selected, value.sequence),
    });
    if ((event.type === 'select' || (event.type === 'board' && event.event?.action === 'pane')) && matchMedia('(max-width: 760px)').matches) setSidebar(false);
    syncSidebar();
    if (surface.selected !== previousSelection) liveFollow = true;
    if (event.type === 'history') {
      liveFollow = event.after === null;
      if (liveFollow) surface.scrollToBottom(); else surface.showHistory();
    }
    streams.surface(liveFollow ? surface.liveRoot : null, surface.selected, value.sequence);
    if (!result.receipt.ok) throw new Error(result.receipt.error?.message ?? 'Request was not accepted');
    report();
  });
  // Keep the queue usable after failures, but propagate rejection to the form
  // so its draft is retained and the error appears beside the submitted input.
  requests = next.catch(error => {
    if (epoch !== generation || error.name === 'AbortError') return;
    if (error.status === 401) { setAccess(true); status('Access token required', 'disconnected'); }
    report(error.message);
  });
  return next;
}

function refresh() {
  const flags = refreshState;
  const epoch = generation;
  flags.again = true;
  if (flags.queued) return;
  flags.queued = true;
  (async () => {
    do { flags.again = false; await dispatch({ type: 'refresh' }); }
    while (flags.again && epoch === generation);
  })().catch(() => {}).finally(() => { flags.queued = false; });
}

async function watch(signal, epoch, credential) {
  while (!signal.aborted && epoch === generation) {
    try {
      const response = await fetch(`/api/events?after=${revision}`, {
        headers: { authorization: `Bearer ${credential}` }, signal });
      if (!response.ok || !response.body) throw new Error(`Event connection: HTTP ${response.status}`);
      if (epoch !== generation) { await response.body.cancel(); return; }
      status('Connected', 'connected');
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      const frames = new EventFrames(notice => {
        if (epoch !== generation) return;
        if (notice.type === 'commit') {
          if (!Number.isSafeInteger(notice.sequence) || notice.sequence < 0) throw new Error('Invalid event revision');
          revision = Math.max(revision, notice.sequence);
          refresh();
        } else if (notice.type === 'fatal') throw new Error(notice.message);
        else streams.receive(notice);
      });
      try {
        for (;;) {
          const { value, done } = await reader.read();
          if (done) { frames.write(decoder.decode()); break; }
          frames.write(decoder.decode(value, { stream: true }));
        }
      } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
      if (!signal.aborted) throw new Error('Event connection closed');
    } catch (error) {
      if (signal.aborted || epoch !== generation) return;
      streams.clear();
      status('Reconnecting', 'connecting');
      report(error.message);
      await new Promise(resolve => {
        const finish = () => { clearTimeout(timer); signal.removeEventListener('abort', finish); resolve(); };
        const timer = setTimeout(finish, 1000);
        signal.addEventListener('abort', finish, { once: true });
      });
    }
  }
}

async function connect() {
  connection?.abort();
  connection = new AbortController();
  generation += 1;
  const epoch = generation;
  const signal = connection.signal;
  requests = Promise.resolve();
  refreshState = { queued: false, again: false };
  state = null;
  revision = 0;
  streams.clear();
  surface?.dispose();
  surface = null;
  $('surface').replaceChildren();
  drafts.clear();
  disclosures.clear();
  if (!token) { setAccess(true); status('Access token required', 'disconnected'); return; }
  store('selvedge-token', token);
  setAccess(false);
  status('Connecting…', 'connecting');
  await dispatch({ type: 'refresh' });
  if (epoch === generation) watch(signal, epoch, token).catch(error => report(error.message));
}

function syncSidebar() {
  const modal = document.body.dataset.sidebar === 'open' && matchMedia('(max-width: 760px)').matches;
  $('sidebar-dismiss').hidden = !modal;
  for (const child of document.querySelector('[data-role="screen"] > .group-content')?.children ?? []) {
    child.inert = modal && child.dataset.role !== 'navigation';
  }
  for (const child of document.querySelectorAll('.board-workspace')) child.inert = modal;
}
function setSidebar(open) {
  document.body.dataset.sidebar = open ? 'open' : 'closed';
  $('sidebar-toggle').setAttribute('aria-expanded', String(open));
  syncSidebar();
}
setSidebar(!matchMedia('(max-width: 760px)').matches);
$('sidebar-toggle').onclick = () => setSidebar(document.body.dataset.sidebar !== 'open');
$('sidebar-dismiss').onclick = () => { setSidebar(false); $('sidebar-toggle').focus(); };
matchMedia('(max-width: 760px)').addEventListener('change', event => setSidebar(!event.matches));
$('theme-toggle').onclick = () => {
  const current = document.documentElement.dataset.theme ?? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  const next = current === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = next; store('selvedge-theme', next);
};
const theme = stored('selvedge-theme');
if (['light', 'dark'].includes(theme)) document.documentElement.dataset.theme = theme;
function setAccess(open) {
  const dialog = $('access');
  if (open) { dialog.hidden = false; if (!dialog.open) dialog.showModal(); $('token').focus(); }
  else { if (dialog.open) dialog.close(); dialog.hidden = true; }
}
$('access-toggle').onclick = () => setAccess(!$('access').open);
$('access-close').onclick = () => setAccess(false);
$('access').addEventListener('close', () => { $('access').hidden = true; });
$('access-form').onsubmit = event => {
  event.preventDefault(); token = $('token').value.trim(); connect().catch(error => report(error.message));
};
window.addEventListener('keydown', event => {
  if (event.key === 'Escape') {
    if (matchMedia('(max-width: 760px)').matches) setSidebar(false);
    document.querySelector('.thread-header button[aria-expanded="true"]')?.click();
    setAccess(false);
    for (const popup of document.querySelectorAll('.compose-mode[open], .form-options[open]')) { popup.open = false; popup.querySelector('summary')?.focus(); }
  }
  if (event.key === 'Tab' && !$('access').open && !$('sidebar-dismiss').hidden) {
    const focusable = [$('sidebar-toggle'), document.querySelector('.brand'), ...document.querySelectorAll('[data-role="navigation"] button:not(:disabled), .app-tools button')].filter(node => node?.getClientRects().length);
    const index = focusable.indexOf(document.activeElement);
    event.preventDefault();
    focusable[(index + (event.shiftKey ? -1 : 1) + focusable.length) % focusable.length]?.focus();
  }
});
document.addEventListener('pointerdown', event => {
  for (const popup of document.querySelectorAll('.compose-mode[open], .form-options[open]')) if (!popup.contains(event.target)) popup.open = false;
});
window.addEventListener('pagehide', () => { connection?.abort(); streams.clear(); surface?.dispose(); });
window.addEventListener('pageshow', event => { if (event.persisted) connect().catch(error => report(error.message)); });
connect().catch(error => report(error.message));
