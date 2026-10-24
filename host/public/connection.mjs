import { EventFrames } from './events.mjs';

/** Observe one authenticated connection. Retry and failure admission belong to the extracted model. */
export async function observeConnection({ request, fetchEvents, signal, sequence, snapshot, ready, notice,
  current = () => !signal.aborted, ownership = () => null, namespace = () => null, refreshNeeded = () => true, publish = () => {} }) {
  const initial = await request('/api/browser/state', signal, true);
  if (!current()) return;
  snapshot(initial, true);
  if (!current()) return;
  ready();
  if (!current()) return;
  const subscribedNamespace = namespace();
  const subscribed = () => current() && namespace() === subscribedNamespace;
  let response;
  let reader;
  let dirty = false;
  let dirtyNoticeCount = 0;
  let flushTimer = null;
  let flushTick = null;
  const flushSignal = Symbol('stream publication');
  const clearFlush = () => {
    if (flushTimer !== null) clearTimeout(flushTimer);
    flushTimer = null;
    flushTick = null;
  };
  const flushStreams = () => {
    const changed = dirty && subscribed();
    clearFlush();
    dirty = false;
    dirtyNoticeCount = 0;
    if (changed) publish();
  };
  const queueStreams = () => {
    if (dirty) return;
    dirty = true;
    flushTick = new Promise(resolve => {
      flushTimer = setTimeout(() => {
        flushTimer = null;
        resolve(flushSignal);
      }, 0);
    });
  };
  try {
    const opening = ownership();
    try { response = await fetchEvents(`/api/events?after=${sequence()}`, signal); }
    catch (error) { error.requestScope = opening; throw error; }
    if (!subscribed()) return;
    // DEFENSE: The SSE endpoint can return an HTTP rejection or a bodyless response instead of an event stream.
    if (!response.ok || !response.body) {
      const error = new Error(`Event connection: HTTP ${response.status}`);
      error.status = response.status;
      error.requestScope = opening;
      throw error;
    }
    reader = response.body.getReader();
    const decoder = new TextDecoder();
    const pending = [];
    const frames = new EventFrames(value => pending.push(value));
    let reading = null;
    let turnStarted = performance.now();
    while (subscribed()) {
      if (performance.now() - turnStarted >= 8) {
        await new Promise(resolve => setTimeout(resolve, 0));
        if (!subscribed()) return;
        turnStarted = performance.now();
      }
      if (pending.length) {
        const event = pending.shift();
        const lifecycle = event.type === 'stream_start' || event.type === 'stream_end' || event.type === 'stream_cancel';
        if (lifecycle || event.type === 'stream-state' || event.type === 'commit' || event.type === 'fatal' ||
            (typeof subscribedNamespace === 'string' && typeof event.namespace === 'string' && event.namespace !== subscribedNamespace)) {
          flushStreams();
          if (!subscribed()) return;
        }
        if (event.type === 'commit') {
          if (refreshNeeded(event)) {
            const body = await request('/api/browser/state', signal, false);
            if (!subscribed()) return;
            snapshot(body, false);
          }
        } else if (event.type === 'fatal') throw new Error(event.message);
        else {
          if (notice(event)) queueStreams();
          if (dirty) dirtyNoticeCount++;
          if (lifecycle || dirtyNoticeCount >= 64) flushStreams();
        }
        continue;
      }
      reading ??= reader.read();
      const received = await (flushTick ? Promise.race([reading, flushTick]) : reading);
      if (!subscribed()) return;
      if (received === flushSignal) { flushStreams(); continue; }
      reading = null;
      // DEFENSE: The service can stop or close its SSE response; report disconnection so the extracted model owns recovery.
      if (received.done) { flushStreams(); throw new Error('Event connection ended'); }
      frames.write(decoder.decode(received.value, { stream: true }));
    }
  } catch (error) {
    // DEFENSE: a read can reject after an accepted snapshot has replaced this
    // subscription's namespace; its failure does not describe the new source.
    if (!subscribed()) return;
    flushStreams();
    throw error;
  } finally {
    clearFlush();
    if (reader) {
      await reader.cancel().catch(error => {
        // DEFENSE: Cancelling an already failed fetch stream rejects with its network TypeError or AbortError.
        if (!(error instanceof TypeError) && error.name !== 'AbortError') throw error;
      });
      reader.releaseLock();
    } else await response?.body?.cancel();
  }
}
