import { EventFrames } from './events.mjs';

/** Observe one authenticated connection. Retry and failure admission belong to Bend. */
export async function observeConnection({ request, fetchEvents, signal, sequence, snapshot, ready, notice }) {
  const initial = await request('/api/browser/state', signal);
  if (signal.aborted) return;
  snapshot(initial);
  ready();
  const response = await fetchEvents(`/api/events?after=${sequence()}`, signal);
  if (!response.ok || !response.body) throw new Error(`Event connection: HTTP ${response.status}`);
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const pending = [];
  const frames = new EventFrames(value => pending.push(value));
  try {
    while (!signal.aborted) {
      const { done, value } = await reader.read();
      if (done) throw new Error('Event connection ended');
      frames.write(decoder.decode(value, { stream: true }));
      for (const event of pending.splice(0)) {
        if (signal.aborted) return;
        if (event.type === 'commit') {
          const current = await request('/api/browser/state', signal);
          if (signal.aborted) return;
          snapshot(current);
        }
        else if (event.type === 'fatal') throw new Error(event.message);
        else notice(event);
      }
    }
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
