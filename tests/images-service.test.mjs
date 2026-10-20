import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { unlink, writeFile } from 'node:fs/promises';
import { imagesFixture, imageBase64, imageBytes, largeImageBytes } from './fixtures/images.mjs';
import { taskIdle } from './support.mjs';

function inputImages(value) {
  if (Array.isArray(value)) return value.flatMap(inputImages);
  if (value === null || typeof value !== 'object') return [];
  if (value.type === 'input_image') return [value];
  return Object.values(value).flatMap(inputImages);
}

function advertisedFunctions(tools, namespace) {
  return tools.flatMap(tool => tool.type === 'namespace'
    ? advertisedFunctions(tool.tools, tool.name) : [{ ...tool, namespace }]);
}

function assertImageBytes(request, count, detail, expectedBase64 = Array(count).fill(imageBase64)) {
  const images = inputImages(request.input);
  assert.equal(images.length, count, 'The actual provider request must contain image blocks, not attachment paths');
  for (const [index, image] of images.entries()) {
    assert.ok(image.image_url === `data:image/png;base64,${expectedBase64[index]}`,
      'The image URL must contain the exact uploaded PNG bytes');
    if (detail !== undefined) assert.equal(image.detail, detail);
  }
}

test('HTTP task images reach the signed-in model on image-only creation, continuation and journal recovery', async t => {
  const fixture = await imagesFixture(t);
  const large = largeImageBytes();
  assert.ok(large.length > 3 * 1024 * 1024);
  const encoded = large.toString('base64');
  const uploaded = await fixture.upload('large RGB screenshot.png', large);
  const { task_id } = await fixture.command({ op: 'create', profile: fixture.profile,
    message: '', images: [uploaded] });
  await taskIdle(fixture.running.service, task_id);
  assert.equal(fixture.requests.length, 1);
  assertImageBytes(fixture.requests[0], 1, 'auto', [encoded]);

  await fixture.command({ op: 'send', task_id, message: '', images: [uploaded] });
  await taskIdle(fixture.running.service, task_id);
  assert.equal(fixture.requests.length, 2);
  assertImageBytes(fixture.requests[1], 2, 'auto', [encoded, encoded]);

  await fixture.restart();
  await fixture.command({ op: 'send', task_id, message: 'Compare the two earlier images.' });
  await taskIdle(fixture.running.service, task_id);
  assert.equal(fixture.requests.length, 3);
  assertImageBytes(fixture.requests[2], 2, 'auto', [encoded, encoded]);
  assert.deepEqual(fixture.upstream.failures, []);
});

test('a board image attachment becomes model input when its assigned card starts', async t => {
  const fixture = await imagesFixture(t);
  const uploaded = await fixture.upload('board evidence.png');
  const created = await fixture.command({ op: 'create_card', title: 'Inspect board evidence',
    description: 'Read the image before deciding.', assignee: `profile/${fixture.profile}`, attachments: [uploaded] });
  const { card_id } = created;
  const card = await fixture.command({ op: 'read_card', card_id });
  await fixture.command({ op: 'run_card', card_id, revision: card.revision });
  const { task_id } = await fixture.command({ op: 'read_card', card_id });
  assert.equal(typeof task_id, 'number');
  await taskIdle(fixture.running.service, task_id);
  assert.equal(fixture.requests.length, 1);
  assertImageBytes(fixture.requests[0], 1, 'auto');
  assert.deepEqual(fixture.upstream.failures, []);
});

test('local and MCP images reach subsequent model turns and preserve their snapshots after restart', async t => {
  let filename;
  const mcpDescription = 'Return an image from the MCP fixture.';
  const mcpImageBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAD0lEQVR4nGNgYPgPRmAKABf2A/1+6zfzAAAAAElFTkSuQmCC';
  // NOTE: Seventeen valid MCP images reproduce the former sixteen-image request rejection.
  const mcpCopies = 17;
  const expectedImages = [imageBase64, ...Array(mcpCopies).fill(mcpImageBase64)];
  const mcpProgram = `
    const { createInterface } = require('node:readline');
    const send = (id, result) => process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\\n');
    createInterface({ input: process.stdin }).on('line', line => {
      const request = JSON.parse(line);
      if (request.id === undefined) return;
      if (request.method === 'initialize') send(request.id, { protocolVersion: request.params.protocolVersion,
        capabilities: { tools: {} }, serverInfo: { name: 'image-fixture', version: '1' } });
      if (request.method === 'tools/list') send(request.id, { tools: [{ name: 'picture',
        description: ${JSON.stringify(mcpDescription)}, inputSchema: { type: 'object', properties: {}, additionalProperties: false } }] });
      if (request.method === 'tools/call') send(request.id, { content: [
        { type: 'text', text: 'Image from the external MCP peer.' },
        ...Array.from({ length: ${mcpCopies} }, () =>
          ({ type: 'image', mimeType: 'image/png', data: ${JSON.stringify(mcpImageBase64)} }))] });
    });`;
  const fixture = await imagesFixture(t, { mcp: { images: { command: process.execPath, args: ['-e', mcpProgram] } },
    respond(body, index) {
      const tools = advertisedFunctions(body.tools);
      if (index === 0) {
        const tool = tools.find(tool => tool.name === 'read_image');
        assert.ok(tool, 'The model must be able to discover the image reader');
        return [{ type: 'function_call', call_id: 'inspect-local-image', name: 'read_image',
          namespace: tool.namespace, arguments: JSON.stringify({ path: filename, detail: 'high' }) }];
      }
      if (index === 1) {
        const tool = tools.find(tool => tool.name === 'mcp__images__picture');
        assert.ok(tool, 'The production MCP connection must publish the external image tool');
        return [{ type: 'function_call', call_id: 'inspect-mcp-image', name: tool.name, namespace: tool.namespace, arguments: '{}' }];
      }
      return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Read both images.' }] }];
    }
  });
  filename = path.join(fixture.workspace, 'local screenshot.png');
  await writeFile(filename, imageBytes);
  const { task_id } = await fixture.command({ op: 'create', profile: fixture.profile, message: `Inspect ${filename}` });
  await taskIdle(fixture.running.service, task_id);
  assert.equal(fixture.requests.length, 3);
  const output = fixture.requests[1].input.find(item => item.type === 'function_call_output' && item.call_id === 'inspect-local-image');
  assert.ok(output, 'The accepted image tool call must settle through its public tool result');
  assertImageBytes(fixture.requests[1], 1, 'high');
  assert.ok(fixture.requests[2].input.some(item => item.type === 'function_call_output' && item.call_id === 'inspect-mcp-image'));
  assertImageBytes(fixture.requests[2], expectedImages.length, undefined, expectedImages);

  await unlink(filename);
  await fixture.restart();
  await fixture.command({ op: 'send', task_id, message: 'Describe the saved image again.' });
  await taskIdle(fixture.running.service, task_id);
  assert.equal(fixture.requests.length, 4);
  assertImageBytes(fixture.requests[3], expectedImages.length, undefined, expectedImages);
  assert.deepEqual(fixture.upstream.failures, []);
});

test('a text-only backend reports unsupported image input without silently sending a text request', async t => {
  const fixture = await imagesFixture(t);
  const uploaded = await fixture.upload();
  const reply = await fixture.rawCommand({ op: 'create', profile: 'text',
    message: 'Inspect this image.', images: [uploaded] });
  const observation = reply.ok
    ? await taskIdle(fixture.running.service, reply.result.task_id)
    : reply;
  const failure = JSON.stringify(observation);
  assert.match(failure, /image|图片/i);
  assert.match(failure, /support|支持/i);
  assert.equal(fixture.requests.length, 0, 'A rejected image must never become a text-only external request');
  assert.equal(fixture.textBackend.requests.length, 0, 'The unsupported backend must never receive a text-only fallback');
  assert.deepEqual(fixture.textBackend.failures, []);
  assert.deepEqual(fixture.upstream.failures, []);
});
