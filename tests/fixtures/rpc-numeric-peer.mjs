import { createInterface } from 'node:readline';

const tool = { name: 'echo', description: 'Report the requested numeric-id fixture case.',
  inputSchema: { type: 'object', properties: { style: { type: 'string' } }, required: ['style'], additionalProperties: false } };
const spell = (id, style) => style === 'decimal' ? `${id}.0` : style === 'compensated' ? `${id}00e-2` : `${id}e0`;
const result = text => ({ content: [{ type: 'text', text }], isError: false });

// JSON.stringify would erase the wire spelling that this public peer exercises.
function send(id, value) {
  process.stdout.write(`{"jsonrpc":"2.0","id":${id},"result":${JSON.stringify(value)}}\n`);
}

let retired;
createInterface({ input: process.stdin }).on('line', line => {
  const request = JSON.parse(line);
  if (!Object.hasOwn(request, 'id')) return;
  const id = request.id;
  if (request.method === 'initialize') {
    send(spell(id, 'decimal'), { protocolVersion: request.params.protocolVersion,
      capabilities: { tools: {} }, serverInfo: { name: 'numeric-id-peer', version: '1' } });
  } else if (request.method === 'tools/list') {
    send(spell(id, 'exponent'), { tools: [tool] });
  } else if (request.method === 'tools/call') {
    for (const wrong of [JSON.stringify(String(id)), String(id + 100), `${id}.0000000000000000001`,
      '9007199254740993', String(retired)]) send(wrong, result('WRONG_ID_MUST_NOT_SETTLE'));
    const { style } = request.params.arguments;
    send(spell(id, style), result(`NUMERIC_ID_ACCEPTED_${style}`));
  } else {
    throw new Error(`Unexpected fixture request: ${request.method}`);
  }
  retired = id;
});
