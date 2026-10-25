import http from 'node:http';

// A loopback ChatGPT Web API peer; it owns protocol resources, never task state.
export async function webPeer(t, respond) {
  const requests = [], controls = [], failures = [], resources = new Map();
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const raw = Buffer.concat(chunks).toString('utf8');
      if (request.url !== '/v1/responses') {
        controls.push(request.url);
        response.writeHead(500); response.end(); return;
      }
      const body = JSON.parse(raw), id = `web-resource-${requests.length + 1}`;
      const entry = { body, raw, key: request.headers['idempotency-key'], authorization: request.headers.authorization };
      requests.push(entry);
      const resource = (output, status = 'completed') => ({ id, object: 'web.response',
        protocol: 'chatgpt-web.v1', created_at: 1790000000,
        previous_response_id: body.previous_response_id ?? null,
        model: body.model ?? resources.get(body.previous_response_id)?.model,
        status, output, usage: status === 'completed'
          ? { input_tokens: 10, output_tokens: 2, total_tokens: 12, estimated: true } : null });
      const start = () => response.writeHead(200, { 'content-type': 'text/event-stream',
        'x-response-id': id, 'x-web-protocol': 'chatgpt-web.v1' });
      const event = (name, value) => response.write(`event: ${name}\r\ndata: ${JSON.stringify(value)}\r\n\r\n`);
      const output = await respond(entry, { response, id, resource, start, event });
      if (output === undefined) return;
      const completed = resource(output); resources.set(id, completed);
      start();
      event('response.in_progress', { response_id: id, previous_response_id: body.previous_response_id ?? null });
      // Multiple data lines join as JSON whitespace; byte writes also split UTF-8 and CRLF framing.
      for (const byte of Buffer.from(`event: response.completed\r\ndata: {"response":\r\ndata: ${JSON.stringify(completed)}}\r\n\r\ndata: [DONE]\r\n\r\n`)) {
        response.write(Buffer.from([byte]));
      }
      response.end();
    // DEFENSE: A malformed actual HTTP request or failed peer assertion must fail the test and terminate its response.
    })().catch(error => { failures.push(error); response.destroy(error); });
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
  });
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return { endpoint: `http://127.0.0.1:${server.address().port}/v1/responses`, requests, controls, failures };
}
