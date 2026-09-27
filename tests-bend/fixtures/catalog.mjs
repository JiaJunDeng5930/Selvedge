import { readFileSync, writeFileSync, watchFile, unwatchFile } from 'node:fs';
import { createInterface } from 'node:readline';

const filename = process.env.SELVEDGE_FIXTURE_CATALOG;
const send = value => process.stdout.write(`${JSON.stringify(value)}\n`);
watchFile(filename, { interval: 20 }, () => send({ jsonrpc: '2.0', method: 'notifications/tools/list_changed' }));
for await (const line of createInterface({ input: process.stdin })) {
  const request = JSON.parse(line);
  if (request.id === undefined) continue;
  if (request.method === 'initialize') {
    send({ jsonrpc: '2.0', id: request.id, result: { protocolVersion: request.params.protocolVersion,
      capabilities: { tools: { listChanged: true } }, serverInfo: { name: 'catalog-fixture', version: '1' } } });
  } else if (request.method === 'tools/list') {
    const state = JSON.parse(readFileSync(filename, 'utf8'));
    if (state.block) { writeFileSync(`${filename}.blocked`, 'discovery is pending'); continue; }
    send({ jsonrpc: '2.0', id: request.id, result: { tools: state.tools } });
  } else send({ jsonrpc: '2.0', id: request.id, error: { code: -32601, message: 'Unknown fixture method' } });
}
unwatchFile(filename);
