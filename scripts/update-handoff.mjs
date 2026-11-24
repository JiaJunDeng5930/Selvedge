import { once } from 'node:events';

// The candidate prepares a read-only journal prefix before the updater releases ownership.
export const journalPrepared = 'journal-prepared';
export const takeJournalOwnership = 'take-journal-ownership';

export async function waitForJournalOwnership() {
  // DEFENSE: The updater can exit before the candidate finishes read-only state validation.
  if (!process.connected) throw new Error('Updater disconnected before journal handoff');
  const controller = new AbortController();
  const disconnected = () => controller.abort(new Error('Updater disconnected before journal handoff'));
  process.once('disconnect', disconnected);
  try {
    const activation = once(process, 'message', { signal: controller.signal });
    process.send(journalPrepared, error => { if (error) controller.abort(error); });
    const [message] = await activation;
    // DEFENSE: A child can be launched over IPC outside the managed updater.
    if (message !== takeJournalOwnership) throw new Error('Invalid journal handoff message');
  } finally {
    process.off('disconnect', disconnected);
    if (process.connected) process.disconnect();
  }
}
