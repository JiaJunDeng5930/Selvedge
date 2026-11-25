import { safeInteger } from './json-tokens.mjs';

export const browserSequenceHeader = 'x-selvedge-browser-sequence';

/** Apply observations produced by the native publication functions. */
export function applyProgramUpdates(program, updates) {
  let tasks = program.tasks;
  if (!updates.length) return program;
  const shared = { ...program };
  for (const update of updates) {
    Object.assign(shared, update.shared);
    if (tasks === program.tasks && (update.tasks.length || update.references.length))
      tasks = tasks.slice();
    for (const row of update.tasks) {
      const id = safeInteger(row.id);
      const previous = tasks[id]?.history ?? [];
      const history = row.appended.length ? previous.concat(row.appended) : previous;
      tasks[id] = { ...row.value, history };
    }
    for (const row of update.references) {
      const id = safeInteger(row.id);
      tasks[id] = { ...tasks[id], ...row.value };
    }
  }
  shared.tasks = tasks;
  return shared;
}
