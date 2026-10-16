import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Journal } from '../../host/journal.mjs';

export const environment = {
  kind: 'configure', instructions: { configured: 'Task graph fixture', global: null },
  profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture-model', reasoning_options: null }],
  tools: [], max_fork: 4, max_descendants: 8,
};
export const output = { kind: 'output' };
export const literal = value => ({ kind: 'literal', value });
export const concat = (...parts) => ({ kind: 'concat', parts });
export const node = (key, message = key, extra = {}) => ({ key, profile: 'fixture', message, ...extra });
export const reference = (key, task_id) => ({ key, task_id });
export const rule = (key, source, ...actions) => ({ key, source, actions });
export const action = (target, message = output) => ({ target, message });
export const command = command => ({ kind: 'command', command });
export const model = (effect, items) => ({ kind: 'model', task_id: effect.task_id,
  ticket: effect.ticket, ok: true, items });
export const say = text => ({ type: 'text', text });

export async function journalFixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-task-graph-'));
  const filename = path.join(directory, 'journal.sqlite');
  let journal = await Journal.open(filename);
  t.after(async () => { await journal.close(); await rm(directory, { recursive: true, force: true }); });
  assert.equal((await journal.execute(environment)).reply.ok, true);
  return {
    filename,
    get journal() { return journal; },
    send: input => journal.execute(input),
    command: body => journal.execute(command(body)),
    async reopen() { await journal.close(); journal = await Journal.open(filename); return journal; },
  };
}

export async function install(fixture, nodes, rules, extra = {}) {
  const decision = await fixture.command({ op: 'create_task_graph', name: 'Paired work', nodes, rules, ...extra });
  assert.equal(decision.reply.ok, true, JSON.stringify(decision.reply));
  assert.equal(typeof decision.reply.result.graph_id, 'number');
  const graph = (await fixture.command({ op: 'read_task_graph', graph_id: decision.reply.result.graph_id })).reply;
  assert.equal(graph.ok, true, JSON.stringify(graph));
  return { decision, graph: graph.result };
}

export function taskId(graph, key) {
  const node = graph.nodes.find(node => node.key === key);
  assert.ok(node, `Missing resolved graph node ${key}`);
  return node.task_id;
}

export function modelEffect(decision, task_id, kind = 'model') {
  const effect = decision.effects.find(effect => effect.kind === kind && effect.task_id === task_id);
  assert.ok(effect, `Missing ${kind} effect for task ${task_id}: ${JSON.stringify(decision.effects)}`);
  return effect;
}

export async function page(fixture, task_id) {
  const decision = await fixture.command({ op: 'read', task_id });
  assert.equal(decision.reply.ok, true, JSON.stringify(decision.reply));
  return decision.reply.result;
}

export async function readGraph(fixture, graph_id) {
  const decision = await fixture.command({ op: 'read_task_graph', graph_id });
  assert.equal(decision.reply.ok, true, JSON.stringify(decision.reply));
  return decision.reply.result;
}
