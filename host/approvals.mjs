import { parseJson } from './codec.mjs';
import { requestModel } from './providers.mjs';

// The wire contract has exactly two string members. Checking this grammar before
// parsing prevents duplicate (including escaped) keys from silently overwriting
// a denial. JSON.parse and the checks below still validate syntax and values.
const jsonString = String.raw`"(?:[^"\\\u0000-\u001f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"`;
const twoStringMembers = new RegExp(String.raw`^\s*\{\s*${jsonString}\s*:\s*${jsonString}\s*,\s*${jsonString}\s*:\s*${jsonString}\s*\}\s*$`);

/** Decode one untrusted provider response. No heuristic, code fence or tool call grants access. */
export function approvalOutcome(items, limit) {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new TypeError('Missing native approval response bound');
  if (!Array.isArray(items)) throw new TypeError('The approval reviewer must return text without tool calls');
  const texts = [];
  for (const item of items) {
    if (item?.type === 'text' && typeof item.text === 'string') texts.push(item.text);
    else if (item?.type === 'context' && item.value?.type === 'reasoning') continue;
    else if (item?.type === 'context' && item.value?.type === 'message' && item.value.role === 'assistant' &&
        Array.isArray(item.value.content) && item.value.content.length === 1 && item.value.content[0]?.type === 'output_text') {
      texts.push(item.value.content[0].text);
    } else throw new TypeError('The approval reviewer must return text without tool calls');
  }
  if (texts.length !== 1) throw new TypeError('The approval reviewer must return exactly one decision');
  const text = texts[0];
  if (typeof text !== 'string' || !text.isWellFormed() || Buffer.byteLength(text) > limit + 256) {
    throw new TypeError('The approval reviewer exceeded its response bound');
  }
  if (!twoStringMembers.test(text)) throw new TypeError('The approval reviewer must return exactly two string fields');
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
