import { boundary, observeJson } from './public/model-boundary.mjs';
import { requestModel } from './providers.mjs';

/** Decode the observed provider response through the native admission. */
export function approvalOutcome(items, limit, context = null) {
  const text = boundary('effect.approval_text', { items, limit, context });
  return boundary('effect.approval_outcome', { items, text, observation: observeJson(text), limit, context });
}

/** A single independent provider request; this never creates or advances a task. */
export async function requestApproval(effect, config, home, limits, { signal } = {}) {
  boundary('effect.request_approval', { effect, config, home, limits });
  const items = await requestModel(effect, config, home, limits, { signal });
  return approvalOutcome(items, limits.approval_reason_bytes, effect);
}
