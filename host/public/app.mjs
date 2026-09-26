import { mount } from './renderer.mjs';

const $ = id => document.getElementById(id);
let token = new URLSearchParams(location.hash.slice(1)).get('token') || sessionStorage.getItem('selvedge-token') || '';
if (location.hash) history.replaceState(null, '', location.pathname);
let state = null;
let revision = 0;
let requests = Promise.resolve();
let refreshQueued = false;
let refreshAgain = false;
let connection;
let generation = 0;
const drafts = new Map();
const disclosures = new Map();

function report(message = '') {
  $('error').textContent = message;
  $('error').hidden = !message;
}

async function api(body, signal) {
  const response = await fetch('/api/ui', { method: 'POST', signal,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const value = await response.json();
  if (response.status === 401) $('access').hidden = false;
  if (!response.ok || !value.ok) throw new Error(value.error?.message ?? `HTTP ${response.status}`);
  revision = Math.max(revision, value.sequence);
  return value.result;
}

// Serialize navigation and submissions. No client copy of a task or command
// table exists: the opaque cursor and unsubmitted widget drafts are UI state.
function dispatch(event, formKey) {
  const epoch = generation;
  const next = requests.then(async () => {
    if (epoch !== generation) return;
    const result = await api({ state, event }, connection?.signal);
    if (epoch !== generation) return;
    state = result.presentation.state;
    if (formKey && result.receipt.ok) {
      for (const key of drafts.keys()) if (key.startsWith(`${formKey}/`)) drafts.delete(key);
    }
    mount($('surface'), result.presentation.root, dispatch, { drafts, disclosures });
    report();
  });
  requests = next.catch(error => { if (epoch === generation && error.name !== 'AbortError') report(error.message); });
  return requests;
}

function refresh() {
  refreshAgain = true;
  if (refreshQueued) return;
  refreshQueued = true;
  (async () => {
    do { refreshAgain = false; await dispatch({ type: 'refresh' }); } while (refreshAgain);
  })().finally(() => { refreshQueued = false; });
}

async function watch(signal, epoch) {
  while (!signal.aborted && epoch === generation) {
    try {
      const response = await fetch(`/api/events?after=${revision}`, {
        headers: { authorization: `Bearer ${token}` }, signal });
      if (!response.ok || !response.body) throw new Error(`Event connection: HTTP ${response.status}`);
      $('connection').textContent = 'Connected';
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let pending = '';
      try {
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          pending += decoder.decode(value, { stream: true }).replaceAll('\r\n', '\n');
          let end;
          while ((end = pending.indexOf('\n\n')) >= 0) {
            const frame = pending.slice(0, end);
            pending = pending.slice(end + 2);
            const data = frame.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n');
            if (!data) continue;
            const notice = JSON.parse(data);
            // SSE invalidates the surface; it never tells the adapter how to
            // interpret domain state, model deltas, tool outcomes or controls.
            if (notice.type === 'commit') { revision = Math.max(revision, notice.sequence); refresh(); }
            if (notice.type === 'fatal') throw new Error(notice.message);
          }
          if (pending.length > 4 * 1024 * 1024) throw new Error('Event frame is too large');
        }
      } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
      if (!signal.aborted) throw new Error('Event connection closed');
    } catch (error) {
      if (signal.aborted || epoch !== generation) return;
      $('connection').textContent = 'Reconnecting';
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
  refreshQueued = false;
  refreshAgain = false;
  state = null;
  revision = 0;
  drafts.clear();
  disclosures.clear();
  if (!token) { $('access').hidden = false; $('connection').textContent = 'Access token required'; return; }
  sessionStorage.setItem('selvedge-token', token);
  $('access').hidden = true;
  await dispatch({ type: 'refresh' });
  if (epoch === generation) watch(signal, epoch).catch(error => report(error.message));
}

$('connect').onclick = () => { token = $('token').value.trim(); connect().catch(error => report(error.message)); };
window.addEventListener('pagehide', () => connection?.abort());
connect().catch(error => report(error.message));
