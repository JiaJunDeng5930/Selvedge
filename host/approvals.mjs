import { parseJson } from './codec.mjs';
import { requestModel } from './providers.mjs';

/** Decode one untrusted provider response. No heuristic, code fence or tool call grants access. */
export function approvalOutcome(items, limit) {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new TypeError('Missing native approval response bound');
  if (!Array.isArray(items) || items.some(item => item.type !== 'context' ||
      !['message', 'reasoning'].includes(item.value?.type))) {
    throw new TypeError('The approval reviewer must return text without tool calls');
  }
  const messages = items.filter(item => item.value.type === 'message');
  if (messages.length !== 1 || messages[0].value.role !== 'assistant' ||
      !Array.isArray(messages[0].value.content) || messages[0].value.content.length !== 1 ||
      messages[0].value.content[0]?.type !== 'output_text') {
    throw new TypeError('The approval reviewer must return exactly one decision');
  }
  const text = messages[0].value.content[0].text;
  if (typeof text !== 'string' || !text.isWellFormed() || Buffer.byteLength(text) > limit + 256) {
    throw new TypeError('The approval reviewer exceeded its response bound');
  }
  const value = parseJson(text);
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== 2 || !Object.hasOwn(value, 'decision') || !Object.hasOwn(value, 'reason') ||
      !['allow', 'deny'].includes(value.decision) || typeof value.reason !== 'string' ||
      !value.reason.trim() || !value.reason.isWellFormed() || value.reason.includes('\0') || Buffer.byteLength(value.reason) > limit) {
    throw new TypeError('The approval reviewer returned a malformed decision');
  }
  return value;
}

/** A single independent provider request; this never creates or advances a task. */
export async function requestApproval(effect, config, home, limits, { signal } = {}) {
  if (effect.kind !== 'approval') throw new TypeError('Expected a committed approval effect');
  const items = await requestModel(effect, config, home, limits, { signal });
  return approvalOutcome(items, limits.approval_reason_bytes);
}
