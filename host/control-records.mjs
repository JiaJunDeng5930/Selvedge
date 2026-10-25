import { parseJson, stringifyJson } from './codec.mjs';
import { publishBytes, readBoundedRegularSnapshot } from './file-io.mjs';
export { durableDirectory, syncDirectory } from './file-io.mjs';

export async function writeControlRecord(filename, value) {
  await publishBytes(filename, stringifyJson(value));
}

/** Read one bounded control-file revision without following replaced links. */
export async function readControlRecord(filename, { maximumBytes, label }) {
  let snapshot;
  try { snapshot = await readBoundedRegularSnapshot(filename, { maximumBytes }); }
  catch (error) {
    // DEFENSE: Control records externally replaced with special, oversized or changing files are invalid.
    if (['NOT_REGULAR', 'TOO_LARGE', 'CHANGED'].includes(error.code)) throw new Error(`Invalid ${label}: ${error.message}`);
    throw error;
  }
  return parseJson(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(snapshot.bytes));
}
