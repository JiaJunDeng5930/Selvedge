import { safeInteger } from './json-tokens.mjs';

export const browserSequenceHeader = 'x-selvedge-browser-sequence';
export const browserOutlineHeader = 'x-selvedge-browser-outline';
export const browserHistoryTasksHeader = 'x-selvedge-browser-history-tasks';
const retainedTaskFields = ['tools', 'context', 'cursor', 'has_assistant_reply', 'execution_failed', 'card_link_stage'];

// Task identities are admitted as unsigned 32-bit integers. Each level
// addresses four bits. The browser and Journal share immutable task subtrees.
const lastTaskLevel = 7;
const taskSlot = (id, level) => (id >>> (4 * level)) & 15;

function writeTaskSlot(slots, level, id, row, copy) {
  const position = taskSlot(id, level);
  const next = copy ? slots.slice() : slots;
  while (next.length <= position) next.push(null);
  next[position] = level === 0 ? row : writeTaskSlot(next[position] ?? [], level - 1, id, row, copy);
  return next;
}

export function indexProgramTasks(program) {
  const slots = [];
  for (const row of program.tasks) writeTaskSlot(slots, lastTaskLevel, safeInteger(row.id), row, false);
  return { ...program, tasks: { slots } };
}

export function programTask(tasks, id) {
  let slot = tasks.slots;
  for (let level = lastTaskLevel; level >= 0 && slot != null; level--)
    slot = slot[taskSlot(id, level)];
  return slot ?? undefined;
}

export function replaceProgramTask(program, id, row) {
  return { ...program, tasks: { slots: writeTaskSlot(program.tasks.slots, lastTaskLevel, id, row, true) } };
}

export function programWithTaskArray(program) {
  const tasks = [];
  function collect(slots, level) {
    for (const slot of slots) {
      if (slot === null) continue;
      if (level === 0) tasks.push(slot);
      else collect(slot, level - 1);
    }
  }
  collect(program.tasks.slots, lastTaskLevel);
  return { ...program, tasks };
}

export function installBrowserHistory(task, history) {
  const { history: previous, history_pending, ...facts } = task;
  if (history === undefined) return { ...facts, history_pending: true };
  const pending = history.length !== safeInteger(task.cursor) || (history.length !== 0 && task.tools === undefined);
  return pending ? { ...facts, history, history_pending: true } : { ...facts, history };
}

export function browserOutline(program) {
  const snapshot = programWithTaskArray(program);
  return { ...snapshot, tasks: snapshot.tasks.map(task => {
    const { history, tools, ...outline } = task;
    return history.length ? { ...outline, history_pending: true } : { ...outline, history };
  }) };
}

export function retainBrowserHistory(program, previous) {
  return indexProgramTasks({ ...program, tasks: program.tasks.map(task => {
    const prior = programTask(previous.tasks, safeInteger(task.id));
    const facts = prior?.tools === undefined ? task : { tools: prior.tools, ...task };
    return installBrowserHistory(facts, task.history ?? prior?.history);
  }) });
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
  let slots = program.tasks.slots;
  if (!updates.length) return program;
  const shared = { ...program };
  for (const update of updates) {
    Object.assign(shared, update.shared);
    for (const row of update.tasks) {
      const id = safeInteger(row.id);
      const prior = programTask({ slots }, id);
      const previous = prior?.history;
      const prefix = previous ?? [];
      const data = { ...row.value };
      for (const field of retainedTaskFields)
        if (prior?.[field] !== undefined && !Object.hasOwn(data, field)) data[field] = prior[field];
      const start = safeInteger(data.cursor) - row.appended.length;
      const history = prefix.length === start ? (row.appended.length ? prefix.concat(row.appended) : prefix) : previous;
      const observed = installBrowserHistory({ ...data, fork: { ...prior?.fork, ...data.fork } }, history);
      slots = writeTaskSlot(slots, lastTaskLevel, id, observed, true);
    }
    for (const row of update.references) {
      const id = safeInteger(row.id);
      slots = writeTaskSlot(slots, lastTaskLevel, id, { ...programTask({ slots }, id), ...row.value }, true);
    }
  }
  shared.tasks = slots === program.tasks.slots ? program.tasks : { slots };
  return shared;
}
