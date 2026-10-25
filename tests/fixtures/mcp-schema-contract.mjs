import { appendFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { AjvJsonSchemaValidator } from '@modelcontextprotocol/sdk/validation/ajv';

const [mode, log] = process.argv.slice(2);
const inputSchema = {
  type: 'object',
  properties: {
    offset: { type: 'number' },
    readings: { type: 'array', minItems: 1, items: { $ref: '#/$defs/reading' } },
  },
  required: ['offset', 'readings'], additionalProperties: false,
  $defs: { reading: {
    type: 'object', properties: { value: { type: 'number' }, unit: { enum: ['m'] } },
    required: ['value', 'unit'], additionalProperties: false,
  } },
};
const tool = { name: 'measure', description: 'Add metre readings to a signed offset.', inputSchema };

if (mode === 'mcp') {
  const server = new Server({ name: 'schema-contract-fixture', version: '1' }, { capabilities: { tools: {} } });
  const validate = new AjvJsonSchemaValidator().getValidator(inputSchema);
  server.setRequestHandler(ListToolsRequestSchema, () => ({ tools: [tool] }));
  server.setRequestHandler(CallToolRequestSchema, request => {
    appendFileSync(log, JSON.stringify(request.params) + '\n');
    const result = validate(request.params.arguments);
    if (!result.valid) return { isError: true, content: [{ type: 'text', text: 'SERVER_SCHEMA_REJECTED' }] };
    const { offset, readings } = result.data;
    return { isError: false, content: [{ type: 'text', text: JSON.stringify({
      receipt: 'MCP_SCHEMA_ACCEPTED', metres: offset + readings.reduce((sum, reading) => sum + reading.value, 0),
    }) }] };
  });
  await server.connect(new StdioServerTransport());
} else {
  createInterface({ input: process.stdin }).on('line', line => {
    const request = JSON.parse(line);
    if (request.method !== 'initialize' || !Object.hasOwn(request, 'id')) return;
    process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: request.id, result: {
      protocolVersion: request.params.protocolVersion, revision: 'schema-contract-1',
      beforeTool: false, afterTool: false, events: [], tools: [tool],
    } }) + '\n');
  });
}
