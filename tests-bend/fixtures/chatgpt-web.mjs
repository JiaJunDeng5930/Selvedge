import assert from 'node:assert/strict';
import http from 'node:http';
import { createHash } from 'node:crypto';

export const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
export const call = (id, name, args = {}) => ({ type: 'function_call', id: `item_${id}`, call_id: id, name, arguments: args });

// Independent protocol oracle: strict root/continuation fields, homogeneous
// inputs, immutable settings, exact tool batches, named events without a JSON
// `type`, and one successor per response. No commercial account is used.
export async function webServer(t, respond) {
  const requests = [];
  const controls = [];
  const failures = [];
  const resources = new Map();
  const keys = new Map();
  const successors = new Map();
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const raw = Buffer.concat(chunks).toString('utf8');
      const body = raw ? JSON.parse(raw) : undefined;
      assert.equal(request.headers.authorization, 'Bearer local-web-fixture');
      if (request.url !== '/v1/responses') {
        const [, id, action] = /^\/v1\/responses\/([^/]+)(?:\/(resume|cancel))?$/.exec(request.url) ?? [];
        assert.ok(resources.has(id), `Unknown control resource ${id}`);
        controls.push({ id, action: action ?? 'inspect', method: request.method, body });
        response.writeHead(200, { 'content-type': 'application/json' });
        response.end(JSON.stringify(action ? { ok: true, response_id: id } : resources.get(id)));
        return;
      }
      assert.equal(request.method, 'POST');
      assert.equal(request.headers['content-type'], 'application/json');
      const key = request.headers['idempotency-key'];
      assert.match(key, /^[!-~]{1,256}$/);
      requests.push({ body, raw, key, headers: request.headers });
      const identity = { ...body }; delete identity.stream;
      if (keys.has(key)) assert.deepEqual(identity, keys.get(key));
      else keys.set(key, identity);
      if (body.previous_response_id) {
        assert.deepEqual(Object.keys(body).sort(), ['input', 'previous_response_id', 'stream']);
        const predecessor = resources.get(body.previous_response_id);
        assert.ok(predecessor, 'Continuation must select an explicit retained resource');
        assert.ok(!successors.has(predecessor.id) || successors.get(predecessor.id) === key, 'A response has one successor');
        if (predecessor.status === 'requires_action') {
          assert.deepEqual(body.input.map(item => item.type), predecessor.output.map(() => 'function_call_output'));
          assert.deepEqual([...body.input.map(item => item.call_id)].sort(), [...predecessor.output.map(item => item.call_id)].sort());
        } else assert.ok(body.input.every(item => item.type === 'message'));
        successors.set(predecessor.id, key);
      } else {
        assert.ok(Object.keys(body).every(key => ['model', 'input', 'stream', 'instructions', 'tools', 'text'].includes(key)));
        assert.match(body.model, /^chatgpt-web\/(light|medium|high|xhigh|pro)$/);
        assert.ok(body.input.every(item => item.type === 'message'));
        for (const tool of body.tools ?? []) assert.deepEqual(Object.keys(tool).sort(), ['description', 'name', 'parameters', 'type']);
      }
      assert.ok(Array.isArray(body.input) && body.input.length);
      const id = `resp_${createHash('sha256').update(key).digest('hex')}`;
      const previous = resources.get(body.previous_response_id);
      const makeResource = (output, status = output?.[0]?.type === 'function_call' ? 'requires_action' : 'completed') => ({
        id, object: 'web.response', protocol: 'chatgpt-web.v1', created_at: 1790000000,
        previous_response_id: body.previous_response_id ?? null, status, model: body.model ?? previous.model,
        output, usage: status === 'completed' ? { input_tokens: 10, output_tokens: 2, total_tokens: 12, estimated: true } : null,
      });
      const event = (name, value) => response.write(`event: ${name}\r\ndata: ${JSON.stringify(value)}\r\n\r\n`);
      const custom = await respond(body, requests.length - 1, { request, response, id, makeResource, event, resources });
      if (custom === undefined) return;
      const resource = custom.resource ?? makeResource(custom.output ?? answer('done'), custom.status);
      resources.set(id, resource);
      response.writeHead(200, { 'content-type': custom.json ? 'application/json' : 'text/event-stream',
        'x-response-id': id, 'x-web-protocol': 'chatgpt-web.v1', location: `/v1/responses/${id}` });
      if (custom.json) { response.end(JSON.stringify(resource)); return; }
      event('response.in_progress', { response_id: id, previous_response_id: body.previous_response_id ?? null });
      for (const snapshot of custom.snapshots ?? []) event('response.output_text.snapshot', { response_id: id, text: snapshot, provisional: true });
      if (custom.interrupted) { response.end(); return; }
      event(`response.${resource.status}`, { response: resource });
      response.end('data: [DONE]\r\n\r\n');
    })().catch(error => {
      failures.push(error);
      if (!response.headersSent) response.writeHead(500);
      response.end('fixture rejected request');
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return { endpoint: `http://127.0.0.1:${server.address().port}/v1/responses`, requests, controls, failures, resources };
}
