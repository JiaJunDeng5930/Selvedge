#!/usr/bin/env bun
import { createInterface } from 'node:readline';
import { appendFile } from 'node:fs/promises';

// A language-neutral plugin example. stdout is reserved for JSON-RPC; ordinary
// diagnostics go to stderr. Change revision whenever policy or tools change.
const requested = Number(process.env.SELVEDGE_BASH_DEADLINE_MS ?? 30_000);
// DEFENSE: The user-supplied deadline environment variable can be nonnumeric or outside the supported Bash timeout range.
if (!Number.isSafeInteger(requested) || requested < 100 || requested > 1_800_000) throw new Error('Invalid SELVEDGE_BASH_DEADLINE_MS');
const destination = process.env.SELVEDGE_AUDIT_FILE;
let writes = Promise.resolve();

function reply(id, result) {
  process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, result })}\n`);
}

async function handle({ id, method, params }) {
  // DEFENSE: JSON-RPC cancellation notifications have no id and require no reply for these short calls.
  if (id === undefined) return;
  switch (method) {
    case 'initialize':
      // DEFENSE: A JSON-RPC peer can request a plugin protocol this example does not implement.
      if (params.protocolVersion !== 'selvedge-plugin-2') throw new Error('Unsupported plugin protocol');
      reply(id, { protocolVersion: params.protocolVersion, revision: `audit-2-deadline-${requested}`, beforeTool: true, afterTool: true,
        events: params.events,
        tools: [{ name: 'text_metrics', description: 'Count Unicode code points and UTF-8 bytes in text',
          inputSchema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'], additionalProperties: false } }] });
      return;
    case 'beforeTool': {
      // An operational deadline is a useful example policy, not a sandbox for
      // untrusted shell commands. The native kernel validates rewritten args.
      const call = params.call;
      if (call.name !== 'bash') { reply(id, { decision: 'allow' }); return; }
      // DEFENSE: beforeTool sees model arguments before native rewritten-argument validation; reject a missing Bash command.
      if (typeof call.arguments.command !== 'string') { reply(id, { decision: 'deny', reason: 'Bash requires a command string' }); return; }
      const current = call.arguments.timeout_ms;
      // DEFENSE: Model arguments can request an invalid deadline before the native tool contract validates the rewrite.
      if (current !== undefined && (!Number.isSafeInteger(current) || current < 100)) {
        reply(id, { decision: 'deny', reason: 'The requested deadline is invalid' }); return;
      }
      reply(id, { decision: 'rewrite', arguments: { ...call.arguments, timeout_ms: Math.min(current ?? requested, requested) } });
      return;
    }
    case 'afterTool':
      reply(id, { decision: 'allow' });
      return;
    case 'callTool': {
      // DEFENSE: A JSON-RPC peer can call an unknown tool or omit its required text argument.
      if (params.name !== 'text_metrics' || typeof params.arguments?.text !== 'string') throw new Error('Invalid text_metrics call');
      const text = params.arguments.text;
      reply(id, { value: { code_points: [...text].length, utf8_bytes: Buffer.byteLength(text) }, error: false });
      return;
    }
    case 'event':
      if (destination) {
        // Per-process append order is preserved; exactly-once external delivery
        // is not promised. A durable sink can deduplicate sequence + ordinal.
        const operation = writes.then(() => appendFile(destination, `${JSON.stringify(params)}\n`, { mode: 0o600 }));
        // DEFENSE: An append failure is returned by this call; later event writes still get their own attempt in order.
        writes = operation.catch(() => {});
        await operation;
      }
      reply(id, {});
      return;
    case 'ping': reply(id, {}); return;
    // DEFENSE: JSON-RPC peers can send methods absent from this example's current protocol.
    default: throw new Error(`Unsupported method: ${method}`);
  }
}

createInterface({ input: process.stdin }).on('line', line => {
  let request;
  // DEFENSE: A stdio peer can send malformed JSON; report that line and mark this process unsuccessful.
  try { request = JSON.parse(line); }
  catch { console.error('Malformed JSON-RPC input'); process.exitCode = 1; return; }
  // DEFENSE: Unsupported requests or failed audit-file writes require a correlated JSON-RPC error response.
  handle(request).catch(error => {
    process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id: request.id, error: { code: -32000, message: error.message } })}\n`);
  });
});
