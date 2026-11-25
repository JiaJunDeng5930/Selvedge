import { safeInteger } from './json-tokens.mjs';

export const browserSequenceHeader = 'x-selvedge-browser-sequence';
export const browserOutlineHeader = 'x-selvedge-browser-outline';
export const browserHistoryTasksHeader = 'x-selvedge-browser-history-tasks';
const retainedTaskFields = ['tools', 'context', 'cursor', 'has_assistant_reply', 'execution_failed', 'card_link_stage'];

export function installBrowserHistory(task, history) {
  const { history: previous, history_pending, ...facts } = task;
  if (history === undefined) return { ...facts, history_pending: true };
  const pending = history.length !== safeInteger(task.cursor) || (history.length !== 0 && task.tools === undefined);
  return pending ? { ...facts, history, history_pending: true } : { ...facts, history };
}

export function browserOutline(program) {
  return { ...program, tasks: program.tasks.map(task => {
    const { history, tools, ...outline } = task;
    return history.length ? { ...outline, history_pending: true } : { ...outline, history };
  }) };
}

export function retainBrowserHistory(program, previous) {
  return { ...program, tasks: program.tasks.map((task, id) => {
    const prior = previous.tasks[id];
    const facts = prior?.tools === undefined ? task : { tools: prior.tools, ...task };
    return installBrowserHistory(facts, task.history ?? prior?.history);
  }) };
}

export function selectUpdateHistory(update, tasks) {
  const rows = update.tasks.map(row => {
    if (tasks.has(String(row.id)) || (!row.appended.length && row.value.tools === undefined)) return row;
    const { tools, ...value } = row.value;
    return { ...row, value, appended: [] };
  });
  return { ...update, tasks: rows };
}

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
      const prior = tasks[id];
      const previous = prior?.history;
      const prefix = previous ?? [];
      const data = { ...row.value };
      for (const field of retainedTaskFields)
        if (prior?.[field] !== undefined && !Object.hasOwn(data, field)) data[field] = prior[field];
      const start = safeInteger(data.cursor) - row.appended.length;
      const history = prefix.length === start ? (row.appended.length ? prefix.concat(row.appended) : prefix) : previous;
      tasks[id] = installBrowserHistory({ ...data, fork: { ...prior?.fork, ...data.fork } }, history);
    }
    for (const row of update.references) {
      const id = safeInteger(row.id);
      tasks[id] = { ...tasks[id], ...row.value };
    }
  }
  shared.tasks = tasks;
  return shared;
}
