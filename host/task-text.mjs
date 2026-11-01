import { boundary } from './public/model-boundary.mjs';
import { requestModel } from './providers.mjs';

/** One independent request for a committed task title or board drafting ticket. */
export async function requestTaskText(effect, config, home, limits, { signal } = {}) {
  const items = await requestModel(effect, config, home, limits, { signal });
  const text = boundary('effect.task_text_text', { items });
  return boundary('effect.task_text_outcome', { text, context: effect });
}
