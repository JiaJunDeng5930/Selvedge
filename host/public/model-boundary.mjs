import { call } from './generated/host-model.mjs';
import { parseJson, stringifyJson } from './json-tokens.mjs';

function result(text) {
  const envelope = parseJson(text);
  if (envelope.ok) return envelope.value;
  const constructors = { TypeError, RangeError, SyntaxError, Error };
  const ErrorType = constructors[envelope.code] ?? Error;
  const error = new ErrorType(envelope.error);
  if (!Object.hasOwn(constructors, envelope.code)) error.code = envelope.code;
  throw error;
}

/** JSON text is the only representation shared with the extracted OCaml program. */
const cachedOperations = new Set(['config.configuration_head', 'config.context_transport']);
const lastResults = new Map();

export function invoke(entry, operation, source) {
  const input = stringifyJson(source);
  const cacheable = entry === call && cachedOperations.has(operation);
  const previous = cacheable ? lastResults.get(operation) : undefined;
  // Only complete immutable input/output text is retained; callers receive a fresh parsed value.
  const output = previous && previous.input === input ? previous.output : entry(operation, input);
  const value = result(output);
  if (cacheable && (!previous || previous.input !== input)) lastResults.set(operation, { input, output });
  return value;
}
export const boundary = (operation, source) => invoke(call, operation, source);
