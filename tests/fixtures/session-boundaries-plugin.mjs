import { createInterface } from 'node:readline';
import { writeFile } from 'node:fs/promises';

const send = message => process.stdout.write(`${JSON.stringify(message)}\n`);
setInterval(() => {}, 1000);
createInterface({ input: process.stdin }).on('line', async line => {
  const request = JSON.parse(line);
  if (request.method === 'initialize') {
    send({ jsonrpc: '2.0', id: request.id, result: {
      protocolVersion: request.params.protocolVersion, revision: 'session-boundary-1',
      beforeTool: true, afterTool: false, events: [], tools: [{
        name: 'probe', description: 'Observe an extension shutdown boundary.',
        inputSchema: { type: 'object', properties: {}, required: [], additionalProperties: false },
      }],
    } });
  } else if (request.method === 'beforeTool') {
    await writeFile(process.env.SELVEDGE_SESSION_BOUNDARY_MARKER,
      JSON.stringify({ pid: process.pid, method: request.method }));
    // The peer deliberately leaves this real request unanswered until shutdown.
  }
});
