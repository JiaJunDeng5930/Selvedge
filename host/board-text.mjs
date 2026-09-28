import { parseJson } from './codec.mjs';
import { requestModel } from './providers.mjs';

const stringMember = String.raw`"(?:[^"\\\u0000-\u001f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"`;
const pair = new RegExp(String.raw`^\s*\{\s*${stringMember}\s*:\s*${stringMember}\s*,\s*${stringMember}\s*:\s*${stringMember}\s*\}\s*$`);

/** Decode an untrusted, tool-free drafting response; Bend owns its application. */
export function boardTextOutcome(items, maximumBytes) {
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 1) throw new TypeError('Missing board response byte bound');
  if (!Array.isArray(items)) throw new TypeError('The drafting endpoint returned no output');
  const texts = [];
  for (const item of items) {
    if (item?.type === 'text' && typeof item.text === 'string') texts.push(item.text);
    else if (item?.type === 'context' && item.value?.type === 'reasoning') continue;
    else if (item?.type === 'context' && item.value?.type === 'message' && item.value.role === 'assistant' &&
        Array.isArray(item.value.content) && item.value.content.length === 1 && item.value.content[0]?.type === 'output_text') {
      texts.push(item.value.content[0].text);
    } else throw new TypeError('The drafting endpoint must return text without tool calls');
  }
  if (texts.length !== 1 || typeof texts[0] !== 'string' || !texts[0].isWellFormed() || Buffer.byteLength(texts[0]) > maximumBytes) {
    throw new TypeError('The drafting endpoint must return one bounded JSON response');
  }
  if (!pair.test(texts[0])) throw new TypeError('The drafting endpoint must return exactly title and description strings');
  const value = parseJson(texts[0]);
  if (Object.keys(value).length !== 2 || !Object.hasOwn(value, 'title') || !Object.hasOwn(value, 'description') ||
      typeof value.title !== 'string' || typeof value.description !== 'string' || !value.title.trim() ||
      !value.title.isWellFormed() || !value.description.isWellFormed() || value.title.includes('\0') || value.description.includes('\0')) {
    throw new TypeError('The drafting endpoint returned invalid title or description fields');
  }
  return value;
}

/** One request for a committed board ticket. This creates no conversation or tools. */
export async function requestBoardText(effect, config, home, limits, { signal } = {}) {
  if (effect.kind !== 'board_text' || typeof effect.prompt !== 'string') throw new TypeError('Expected a committed board drafting effect');
  if (effect.model?.adaptive_reasoning) throw new TypeError('Board drafting requires an ordinary model profile');
  const items = await requestModel(effect, config, home, limits, { signal });
  return boardTextOutcome(items, limits.frame_bytes);
}
