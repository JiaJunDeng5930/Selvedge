import test from 'node:test';
import assert from 'node:assert/strict';
import { Plugin } from '../host/plugins.mjs';
import { Kernel } from '../host/kernel.mjs';
import { once } from 'node:events';

test('closing a plugin aborts a hung request and reaps the process transport', { timeout: 5000 }, async t => {
  const kernel = new Kernel();
  const description = await kernel.initialize();
  await kernel.close();
  const child = `
    const { createInterface } = require('node:readline');
    const send = message => process.stdout.write(JSON.stringify(message) + '\\n');
    createInterface({ input: process.stdin }).on('line', line => {
      const request = JSON.parse(line);
      if (request.method === 'initialize') send({ jsonrpc: '2.0', id: request.id, result: {
        protocolVersion: request.params.protocolVersion, revision: '1', beforeTool: true, afterTool: false, events: [], tools: [] } });
      if (request.method === 'beforeTool') send({ jsonrpc: '2.0', method: 'fixture.hung', params: {} });
    });`;
  const plugin = new Plugin('hung', { command: process.execPath, args: ['-e', child] }, description.limits, description.plugins);
  t.after(() => plugin.close());
  await plugin.initialize();
  const started = once(plugin, 'notification');
  const pending = plugin.before({ task_id: 0, ticket: 1, plugin: { name: 'hung', revision: '1' }, tool: { name: 'bash' }, call: { id: 'call', name: 'bash', arguments: {} } });
  const rejected = assert.rejects(pending, /closed|cancel|stopped/i);
  assert.equal((await started)[0].method, 'fixture.hung');
  await plugin.close();
  await rejected;
});
