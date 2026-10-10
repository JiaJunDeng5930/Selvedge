import { boundary, observeJson } from './public/model-boundary.mjs';
import { requestModel } from './providers.mjs';

/** Decode the observed provider response through the native admission. */
export function boardTextOutcome(items, maximumBytes, context = null) {
  const text = boundary('effect.board_text_text', { items, maximumBytes, limit: maximumBytes, context });
  return boundary('effect.board_text_outcome', { items, maximumBytes, text, observation: observeJson(text), limit: maximumBytes, context });
}

/** One request for a committed board ticket. This creates no conversation or tools. */
export async function requestBoardText(effect, config, home, limits, { signal } = {}) {
  boundary('effect.request_board_text', { effect, config, home, limits });
  const items = await requestModel(effect, config, home, limits, { signal });
  return boardTextOutcome(items, limits.frame_bytes, effect);
}
