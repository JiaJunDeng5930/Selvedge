import { parseJson, stringifyJson } from './codec.mjs';
import { events, readText } from './network.mjs';
import { resolveAuth } from './auth.mjs';

const text = value => typeof value === 'string' && value.trim().length > 0;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

export function providerInput(history) {
  return history.map(message => {
    switch (message.role) {
      case 'user': case 'assistant': return { role: message.role, content: message.content };
      case 'function_call': return { type: 'function_call', call_id: message.content.id,
        name: message.content.name, arguments: stringifyJson(message.content.arguments) };
      case 'function_output': return { type: 'function_call_output', call_id: message.call_id,
        output: stringifyJson({ value: message.content, is_error: message.is_error }) };
      case 'model_context': return message.content;
      // Runtime failures explain an interruption without inventing an answer
      // from the model, or elevating it to a system/developer instruction.
      case 'error': return { role: 'user', content: `Runtime notice: ${message.content}` };
      default: throw new Error(`Unsupported history role: ${message.role}`);
    }
  });
}

export function providerOutput(output) {
  if (!Array.isArray(output)) throw new Error('Completed response has no output array');
  return output.map(item => {
    if (!object(item)) throw new Error('Provider returned an invalid output item');
    if (item.type === 'function_call') {
      if (item.async === true) throw new Error('Asynchronous provider tool calls are not supported by this sequential task contract');
      if (!text(item.call_id) || !text(item.name) || typeof item.arguments !== 'string') throw new Error('Provider returned a malformed function call');
      const arguments_ = parseJson(item.arguments);
      if (!object(arguments_)) throw new Error('Function arguments must be a JSON object');
      return { type: 'call', id: item.call_id, name: item.name, arguments: arguments_ };
    }
    if (item.type === 'message') {
      if (item.role !== 'assistant' || !Array.isArray(item.content) || item.content.some(part =>
        !object(part) || !['output_text', 'refusal'].includes(part.type) ||
        typeof (part.type === 'refusal' ? part.refusal : part.text) !== 'string')) {
        throw new Error('Provider returned an unsupported assistant message');
      }
    } else if (!['reasoning', 'compaction'].includes(item.type)) {
      throw new Error(`Unsupported provider output type: ${item.type}`);
    }
    // Preserve the original item, including encrypted reasoning and message
    // phase. It is not also stored as Say, which would replay an answer twice.
    return { type: 'context', value: item };
  });
}

export function responseBody(effect) {
  const body = {
    model: effect.model.name, stream: true, store: false,
    instructions: 'You are an assistant working on a persistent Selvedge task. Use the supplied tools when they help complete the user request.',
    input: providerInput(effect.history), reasoning: { effort: effect.model.reasoning },
    tools: effect.tools.map(tool => ({ type: 'function', name: tool.name,
      description: tool.description, parameters: tool.parameters, strict: false })),
    parallel_tool_calls: false,
    include: ['reasoning.encrypted_content'],
  };
  body.tool_choice = effect.callable.length === 0 ? 'none' : {
    type: 'allowed_tools', mode: 'auto', tools: effect.callable.map(name => ({ type: 'function', name })),
  };
  return body;
}

export async function requestModel(effect, config, home, limits, { signal, onDelta = () => {} } = {}) {
  signal?.throwIfAborted();
  const profile = config.profiles[effect.model.profile];
  if (!profile || profile.provider !== effect.model.provider) throw new Error('The frozen model provider is no longer configured');
  if (profile.provider === 'echo') {
    const last = effect.history.findLast(item => item.role === 'user');
    return [{ type: 'text', text: `[Offline demo] ${last?.content ?? 'Task resumed.'}` }];
  }
  const lifetime = signal ? AbortSignal.any([signal, AbortSignal.timeout(profile.timeout_ms)]) : AbortSignal.timeout(profile.timeout_ms);
  const body = stringifyJson(responseBody(effect));
  if (Buffer.byteLength(body) > limits.frame_bytes) throw new RangeError('Provider request exceeds the configured limit');
  let credential;
  const headers = { 'content-type': 'application/json', accept: 'text/event-stream' };
  if (profile.provider === 'chatgpt') {
    credential = await resolveAuth(profile, home, { signal: lifetime });
    headers.authorization = `Bearer ${credential.access_token}`;
    headers['chatgpt-account-id'] = credential.account_id;
  } else {
    const key = process.env[profile.api_key_env];
    if (!key) throw new Error(`Set ${profile.api_key_env} to use this provider`);
    headers.authorization = `Bearer ${key}`;
  }
  const send = () => fetch(profile.endpoint, { method: 'POST', headers, body, signal: lifetime, redirect: 'error' });
  let response = await send();
  if (response.status === 401 && credential) {
    await response.body?.cancel();
    credential = await resolveAuth(profile, home, { signal: lifetime, rejectedToken: credential.access_token });
    headers.authorization = `Bearer ${credential.access_token}`;
    headers['chatgpt-account-id'] = credential.account_id;
    response = await send();
  }
  if (!response.ok) {
    // Drain a bounded error body, but never put arbitrary upstream headers or
    // credential-bearing diagnostics in the durable conversation.
    await readText(response.body, limits.frame_bytes);
    throw new Error(`Model request failed with HTTP ${response.status}`);
  }
  if (!response.headers.get('content-type')?.toLowerCase().includes('text/event-stream')) {
    await response.body?.cancel();
    throw new Error('Provider did not return an SSE response');
  }
  for await (const data of events(response.body, limits.frame_bytes)) {
    if (data === '[DONE]') break;
    const event = parseJson(data);
    if (event.type === 'response.output_text.delta' && typeof event.delta === 'string') {
      onDelta(event.delta);
    } else if (event.type === 'response.completed') {
      if (event.response?.status !== 'completed') throw new Error('Terminal model response is not completed');
      return providerOutput(event.response.output);
    } else if (['error', 'response.failed', 'response.incomplete'].includes(event.type)) {
      throw new Error(`Model stream ended with ${event.type}`);
    }
  }
  throw new Error('Model stream ended without a completed response');
}
