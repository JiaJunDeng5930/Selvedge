import { run } from './generated/host-model.mjs';
import { emitJsonTokens, parseJson } from './json-tokens.mjs';
export { observeJson } from './json-tokens.mjs';

/** Shared token ABI; only the outer adapter envelope controls rejection. */
export function boundary(operation, source) {
  const tokens = [];
  emitJsonTokens(source, token => tokens.push(token));
  let list = { $: 'Nil' };
  for (let index = tokens.length - 1; index >= 0; index--) {
    list = { $: 'Con', head: tokens[index], tail: list };
  }
  const result = parseJson(run(operation, list));
  if (result.ok) return result.value;
  const ErrorConstructor = result.code === 'TypeError' ? TypeError
    : result.code === 'RangeError' ? RangeError
    : result.code === 'SyntaxError' ? SyntaxError
    : Error;
  const error = new ErrorConstructor(result.error);
  if (Object.hasOwn(result, 'code')
    && !['TypeError', 'RangeError', 'SyntaxError', 'Error'].includes(result.code)) {
    error.code = result.code;
  }
  throw error;
}
