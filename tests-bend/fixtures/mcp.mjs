import assert from 'node:assert/strict';
import { appendFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { DatabaseSync } from 'node:sqlite';

const send = value => process.stdout.write(`${JSON.stringify(value)}\n`);
for await (const line of createInterface({ input: process.stdin })) {
  const request = JSON.parse(line);
  if (request.id === undefined) continue;
  let result;
  switch (request.method) {
    case 'initialize':
      result = { protocolVersion: request.params.protocolVersion, capabilities: { tools: {} }, serverInfo: { name: 'fixture', version: '1' } };
      break;
    case 'tools/list':
      result = { tools: [{ name: 'inspect', description: 'Return the supplied text',
        inputSchema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'], additionalProperties: false } }] };
      break;
    case 'tools/call': {
      assert.equal(request.params.name, 'inspect');
      const database = new DatabaseSync(process.env.SELVEDGE_FIXTURE_JOURNAL, { readOnly: true });
      const effects = database.prepare('SELECT decision FROM journal ORDER BY seq').all().flatMap(row => JSON.parse(row.decision).effects);
      database.close();
      assert.equal(effects.filter(effect => effect.kind === 'tool' && effect.call.id === 'mcp-1').length, 1);
      appendFileSync(process.env.SELVEDGE_FIXTURE_MARKER, 'mcp\n');
      result = { content: [{ type: 'text', text: request.params.arguments.text }], isError: false };
      break;
    }
    default:
      send({ jsonrpc: '2.0', id: request.id, error: { code: -32601, message: 'Unknown fixture method' } });
      continue;
  }
  send({ jsonrpc: '2.0', id: request.id, result });
}
