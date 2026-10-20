import { appendFileSync } from 'node:fs';
import { createInterface } from 'node:readline';

const [mode, log] = process.argv.slice(2);
const tools = [
  { name: 'deliver', description: 'Send a foxtrot delivery receipt.', inputSchema: {
    type: 'object', properties: { text: { type: 'string', description: 'PRIVATE_DELIVERY_PARAMETER_DEFINITION' } },
    required: ['text'], additionalProperties: false,
  } },
  ...Array.from({ length: 6 }, (_, index) => ({ name: `z9_exact_${index}`, description: 'An opaque catalog entry.', inputSchema: {
    type: 'object', properties: { code: { type: 'string', description: `PRIVATE_EXACT_PARAMETER_DEFINITION_${index}` } },
    required: ['code'], additionalProperties: false,
  } })),
];
const send = message => process.stdout.write(JSON.stringify(message) + '\n');
const record = event => appendFileSync(log, JSON.stringify({ mode, ...event }) + '\n');

createInterface({ input: process.stdin }).on('line', line => {
  const request = JSON.parse(line);
  if (!Object.hasOwn(request, 'id')) return;
  let result;
  if (request.method === 'initialize') {
    result = mode === 'mcp'
      ? { protocolVersion: request.params.protocolVersion, capabilities: { tools: {} }, serverInfo: { name: 'discovery-fixture', version: '1' } }
      : { protocolVersion: request.params.protocolVersion, revision: 'discovery-acceptance-1', beforeTool: true,
        afterTool: false, events: [], tools: [] };
  } else if (mode === 'mcp' && request.method === 'tools/list') {
    result = { tools };
  } else if (mode === 'mcp' && request.method === 'tools/call') {
    record({ method: request.method, ...request.params });
    result = { content: [{ type: 'text', text: JSON.stringify({ receipt: 'DELIVERED_BY_REAL_MCP_PEER', ...request.params }) }], isError: false };
  } else if (mode === 'policy' && request.method === 'beforeTool') {
    record({ method: request.method, ...request.params });
    result = request.params.call.name === 'mcp__fixture__deliver' && request.params.call.arguments.text === 'deny-by-fixture'
      ? { decision: 'deny', reason: 'Fixture policy denied this delivery.' }
      : { decision: 'allow' };
  } else {
    send({ jsonrpc: '2.0', id: request.id, error: { code: -32601, message: `Unknown fixture method: ${request.method}` } });
    return;
  }
  send({ jsonrpc: '2.0', id: request.id, result });
});
