import { appendFileSync, existsSync, writeFileSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';

const [log, ready, release] = process.argv.slice(2);
const tool = {
  name: 'record_update',
  description: 'Record one durable update receipt.',
  inputSchema: {
    type: 'object', properties: { ticket: { type: 'string' } },
    required: ['ticket'], additionalProperties: false,
  },
};

const server = new Server({ name: 'update-handoff-fixture', version: '1' }, { capabilities: { tools: {} } });
server.setRequestHandler(ListToolsRequestSchema, () => ({ tools: [tool] }));
server.setRequestHandler(CallToolRequestSchema, async request => {
  appendFileSync(log, `${JSON.stringify(request.params.arguments)}\n`);
  writeFileSync(ready, 'running');
  while (!existsSync(release)) await delay(10);
  return { isError: false, content: [{ type: 'text', text: 'UPDATE_TOOL_RECEIPT' }] };
});
await server.connect(new StdioServerTransport());
