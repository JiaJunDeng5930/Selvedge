import { boundary } from './public/model-boundary.mjs';
import { requestModel } from './providers.mjs';

/** Decode the observed provider response through the native admission. */
export function taskTextOutcome(items, maximumBytes, context = null) {
  const text = boundary('effect.task_text_text', { items, maximumBytes, limit: maximumBytes, context });
  return boundary('effect.task_text_outcome', { items, maximumBytes, text, limit: maximumBytes, context });
}

/** One independent request for a committed task title or board drafting ticket. */
export async function requestTaskText(effect, config, home, limits, { signal } = {}) {
  boundary('effect.request_task_text', { effect, config, home, limits });
  const items = await requestModel(effect, config, home, limits, { signal });
  return taskTextOutcome(items, limits.frame_bytes, effect);
}
