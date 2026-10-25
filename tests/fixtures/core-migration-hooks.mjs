import { appendFileSync, existsSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import { createInterface } from 'node:readline';
const [mode, log] = process.argv.slice(2);
const send = value => process.stdout.write(`${JSON.stringify(value)}\n`);
createInterface({ input: process.stdin }).on('line', async line => {
  const request = JSON.parse(line);
  if (!Object.hasOwn(request, 'id')) return;
  let result;
  if (request.method === 'initialize') result = {
    protocolVersion: request.params.protocolVersion, revision: 'core-migration-1',
    beforeTool: mode === 'before', afterTool: mode === 'after', events: mode === 'observer' ? request.params.events : [], tools: [],
  };
  else if (request.method === 'event') {
    appendFileSync(log, `${JSON.stringify(request.params)}\n`);
    result = {};
  } else if (request.method === 'afterTool' || request.method === 'beforeTool') {
    appendFileSync(log, `${JSON.stringify(request.params)}\n`);
    if (mode === 'before') while (!existsSync(`${log}.release`)) await delay(10);
    result = { decision: 'allow' };
  } else {
    send({ jsonrpc: '2.0', id: request.id, error: { code: -32601, message: `Unknown method: ${request.method}` } });
    return;
  }
  send({ jsonrpc: '2.0', id: request.id, result });
});
