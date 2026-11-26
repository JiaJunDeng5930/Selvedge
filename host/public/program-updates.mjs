import { naturalKey, safeInteger } from './json-tokens.mjs';

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
  return { ...program, tasks: indexRows(program.tasks, row => row.id) };
}

function indexRows(rows, identity) {
  if (!Array.isArray(rows)) return rows;
  const slots = [];
  for (const row of rows) writeTaskSlot(slots, lastTaskLevel, safeInteger(identity(row)), row, false);
  return { slots };
}

export function indexProgramCollections(program) {
  return {
    ...program,
    projects: indexRows(program.projects, row => row.id),
    workflow_instances: indexRows(program.workflow_instances, row => row.instance_id),
    board: { ...program.board, cards: indexRows(program.board.cards, row => row.id) },
    card_save_facts: { ...program.card_save_facts, cards: indexRows(program.card_save_facts.cards, row => row[0]) },
  };
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

function collectRows(rows) {
  if (Array.isArray(rows)) return rows;
  const values = [];
  function collect(slots, level) {
    for (const slot of slots) {
      if (slot === null) continue;
      if (level === 0) values.push(slot);
      else collect(slot, level - 1);
    }
  }
  collect(rows.slots, lastTaskLevel);
  return values;
}

export function programWithTaskArray(program) {
  const tasks = collectRows(program.tasks);
  if (Array.isArray(program.projects)) return { ...program, tasks };
  const projects = collectRows(program.projects).sort(projectOrder);
  return {
    ...program, tasks, projects,
    workflow_instances: collectRows(program.workflow_instances),
    board: { ...program.board, cards: collectRows(program.board.cards) },
    card_save_facts: { ...program.card_save_facts, cards: collectRows(program.card_save_facts.cards),
      projects: projectIdentities(projects) },
  };
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

function mergeRows(rows, updates, key, value, order = (left, right) => safeInteger(key(left)) - safeInteger(key(right))) {
  if (!Array.isArray(rows)) {
    let { slots } = rows;
    for (const edit of updates)
      slots = writeTaskSlot(slots, lastTaskLevel, edit.id, edit.value === null ? null : value(edit.value), true);
    return { slots };
  }
  const changed = new Set(updates.map(({ id }) => id));
  return [
    ...rows.filter(row => !changed.has(safeInteger(key(row)))),
    ...updates.flatMap(edit => edit.value === null ? [] : [value(edit.value)]),
  ].sort(order);
}

function projectOrder(left, right) {
  const leftOrder = BigInt(naturalKey(left.sort_order));
  const rightOrder = BigInt(naturalKey(right.sort_order));
  return leftOrder === rightOrder ? safeInteger(left.id) - safeInteger(right.id) : leftOrder > rightOrder ? -1 : 1;
}

function projectIdentities(projects) {
  return projects.map(project => project.id).sort((left, right) => safeInteger(left) - safeInteger(right));
}

/** Apply observations produced by the native publication functions. */
export function applyProgramUpdates(program, updates) {
  let slots = program.tasks.slots;
  if (!updates.length) return program;
  let shared = { ...program };
  const indexedCollections = !Array.isArray(program.projects);
  for (const update of updates) {
    Object.assign(shared, update.shared);
    if (indexedCollections && (update.shared.board || update.shared.card_save_facts))
      shared = indexProgramCollections(shared);
    if (update.projects?.length) {
      shared.projects = mergeRows(shared.projects, update.projects, project => project.id, value => value, projectOrder);
      if (!indexedCollections && shared.card_save_facts) shared.card_save_facts = {
        ...shared.card_save_facts, projects: projectIdentities(shared.projects),
      };
    }
    if (update.cards?.length) {
      shared.board = { ...shared.board,
        cards: mergeRows(shared.board.cards, update.cards, card => card.id, value => value.card) };
      shared.card_save_facts = { ...shared.card_save_facts,
        cards: mergeRows(shared.card_save_facts.cards, update.cards, row => row[0], value => value.facts) };
    }
    if (update.workflowInstances?.length) {
      shared.workflow_instances = mergeRows(shared.workflow_instances, update.workflowInstances,
        instance => instance.instance_id, value => value);
    }
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
