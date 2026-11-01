import { boundary } from './public/model-boundary.mjs';
import { requestModel } from './providers.mjs';

/** A single independent provider request; this never creates or advances a task. */
export async function requestApproval(effect, config, home, limits, { signal } = {}) {
  const items = await requestModel(effect, config, home, limits, { signal });
  const text = boundary('effect.approval_text', { items });
  return boundary('effect.approval_outcome', { text });
}
