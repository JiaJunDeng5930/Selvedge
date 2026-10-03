import assert from 'node:assert/strict';
import { appendFileSync, existsSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { DatabaseSync } from 'node:sqlite';

const name = process.env.PLUGIN_NAME ?? 'guard';
const mode = process.env.PLUGIN_MODE ?? 'normal';
const send = value => process.stdout.write(`${JSON.stringify(value)}\n`);
const log = value => { if (process.env.PLUGIN_LOG) appendFileSync(process.env.PLUGIN_LOG, `${JSON.stringify({ plugin: name, ...value })}\n`); };

function rows() {
  if (!process.env.PLUGIN_JOURNAL) return [];
  const database = new DatabaseSync(process.env.PLUGIN_JOURNAL, { readOnly: true });
  try { return database.prepare('SELECT seq, decision FROM journal ORDER BY seq').all().map(row => ({ sequence: row.seq, ...JSON.parse(row.decision) })); }
  finally { database.close(); }
}

function committed(kind, ticket, taskId) {
  const decisions = rows();
  if (!decisions.length) return;
  assert.equal(decisions.flatMap(row => row.effects).filter(effect => effect.kind === kind && effect.ticket === ticket && effect.task_id === taskId).length, 1);
}

async function respond(request) {
  if (request.id === undefined) { log({ method: request.method, params: request.params }); return; }
  let result;
  switch (request.method) {
    case 'initialize': {
      if (mode === 'slow_initialize') await new Promise(resolve => setTimeout(resolve, 150));
      const schema = mode === 'unsupported_schema'
        ? { type: 'object', properties: { text: { anyOf: [{ type: 'string' }, { type: 'null' }] } } }
        : { type: 'object', properties: { text: { type: 'string' } }, required: ['text'], additionalProperties: false };
      result = { protocolVersion: request.params.protocolVersion, revision: process.env.PLUGIN_REVISION ?? '1', beforeTool: mode !== 'observer', afterTool: process.env.PLUGIN_AFTER === 'true',
        events: process.env.PLUGIN_EVENTS === 'none' ? [] : request.params.events,
        tools: [{ name: 'echo', description: 'Return a bounded value', inputSchema: schema }] };
      if (mode === 'bad_manifest') result.events = ['fabricated_event'];
      if (mode === 'duplicate_tools') result.tools.push(result.tools[0]);
      if (mode === 'bad_name') result.tools[0].name = 'echo/ambiguous';
      if (mode === 'missing_name') delete result.tools[0].name;
      if (mode === 'null_name') result.tools[0].name = null;
      if (mode === 'boolean_name') result.tools[0].name = true;
      break;
    }
    case 'beforeTool': {
      const { task_id, ticket, call, plugin } = request.params;
      assert.equal(plugin.name, name);
      committed('hook', ticket, task_id);
      log({ method: request.method, ...request.params });
      if (mode === 'hang') return;
      if (mode === 'crash') process.exit(18);
      if (mode === 'malformed') result = { decision: 'allow', name: 'fork_task' };
      else if (mode === 'deny' || call.id.includes('denied')) result = { decision: 'deny', reason: 'Fixture policy rejected this call' };
      else if (mode === 'rewrite' && call.name === 'bash') result = { decision: 'rewrite', arguments: { command: process.env.PLUGIN_COMMAND ?? 'printf rewritten' } };
      else if (mode === 'rewrite' && call.name.startsWith('plugin__')) result = { decision: 'rewrite', arguments: { text: 'rewritten by native hook chain' } };
      else result = { decision: 'allow' };
      break;
    }
    case 'callTool': {
      const { context, arguments: args } = request.params;
      committed('tool', context.operation_id, context.task_id);
      log({ method: request.method, ...request.params });
      result = { value: { text: args.text, status: 'running' }, error: false };
      if (process.env.PLUGIN_TOOL_SECRET) result.value = { secret: process.env.PLUGIN_TOOL_SECRET };
      if (process.env.PLUGIN_TOOL_ERROR === 'true') result.error = true;
      break;
    }
    case 'afterTool': {
      const { task_id, ticket, plugin, value } = request.params;
      assert.equal(plugin.name, name);
      committed('after_hook', ticket, task_id);
      log({ method: request.method, ...request.params });
      const decision = process.env.PLUGIN_AFTER_MODE ?? 'allow';
      if (decision === 'hang') return;
      if (decision === 'crash') process.exit(19);
      if (process.env.PLUGIN_AFTER_GATE && request.params.call.id === 'held-result') {
        while (!existsSync(process.env.PLUGIN_AFTER_GATE)) await new Promise(resolve => setTimeout(resolve, 10));
      }
      if (decision === 'malformed') result = { decision: 'rewrite', value: 'invalid', error: false };
      else if (decision === 'deny') result = { decision: 'deny', reason: 'Fixture policy suppresses delivery, not execution' };
      else if (decision === 'redact') result = { decision: 'rewrite', value: { redacted: true, by: name } };
      else if (decision === 'rewrite') result = { decision: 'rewrite', value: { by: name, previous: value } };
      else if (decision === 'null') result = { decision: 'rewrite', value: null };
      else result = { decision: 'allow' };
      break;
    }
    case 'event': {
      const event = request.params;
      const decisions = rows();
      if (decisions.length) {
        const decision = decisions.find(row => row.sequence === event.sequence);
        assert.ok(decision, 'callbacks are post-commit');
        const native = decision.effects.filter(effect => effect.kind === 'plugin_events').flatMap(effect => effect.events)[event.ordinal];
        assert.ok(native.recipients.some(reference => reference.name === name && reference.revision === (process.env.PLUGIN_REVISION ?? '1')));
        const { recipients, ...value } = native;
        assert.deepEqual(event, { sequence: event.sequence, ordinal: event.ordinal, ...value }, 'host never invents domain events');
      }
      log({ method: request.method, ...event });
      if (mode === 'event_hang') return;
      if (mode === 'event_error') { send({ jsonrpc: '2.0', id: request.id, error: { code: -32000, message: 'Observer failed' } }); return; }
      result = {};
      break;
    }
    case 'ping': result = {}; break;
    default:
      send({ jsonrpc: '2.0', id: request.id, error: { code: -32601, message: 'Unknown fixture method' } });
      return;
  }
  send({ jsonrpc: '2.0', id: request.id, result });
}

// Concurrent request handling is essential: a slow observer must not prevent
// this fixture from replying to a separate beforeTool request.
createInterface({ input: process.stdin }).on('line', line => {
  respond(JSON.parse(line)).catch(error => { console.error(error); process.exit(1); });
});
