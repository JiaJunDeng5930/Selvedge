import assert from 'node:assert/strict';
import { appendFileSync } from 'node:fs';
import { createInterface } from 'node:readline';

const log = process.argv[2];
const schema = {
  type: 'object', additionalProperties: false,
  properties: {
    count: { type: 'integer', minimum: 1, maximum: 7 },
    offset: { type: 'integer' },
    nested: { type: 'array', items: { type: 'object', additionalProperties: false,
      properties: { index: { type: 'integer', maximum: 9 } }, required: ['index'] } },
  },
  required: ['count', 'offset', 'nested'],
};

createInterface({ input: process.stdin }).on('line', line => {
  const request = JSON.parse(line);
  if (!Object.hasOwn(request, 'id')) return;
  let result;
  if (request.method === 'initialize') {
    result = { protocolVersion: request.params.protocolVersion, revision: 'natural-parameter-1',
      beforeTool: false, afterTool: false, events: [], tools: [{ name: 'capture',
        description: 'Return the declared integer arguments received by this external process.', inputSchema: schema }] };
  } else {
    assert.equal(request.method, 'callTool');
    appendFileSync(log, `${JSON.stringify(request.params)}\n`);
    result = { value: request.params.arguments, error: false };
  }
  process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id: request.id, result })}\n`);
});
