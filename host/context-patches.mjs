import { diffChars } from 'diff';
import { isDeepStrictEqual } from 'node:util';

const DEFAULT_TIMEOUT = 250;
const DEFAULT_MAX_EDIT_LENGTH = 8192;

export class ContextPatchError extends Error {
  constructor(message, code) {
    super(message);
    this.name = 'ContextPatchError';
    this.code = code;
  }
}

function diffLimits({ timeout = DEFAULT_TIMEOUT, maxEditLength = DEFAULT_MAX_EDIT_LENGTH } = {}) {
  if (!Number.isSafeInteger(timeout) || timeout <= 0) {
    throw new RangeError('Context patch timeout must be a positive safe integer');
  }
  if (!Number.isSafeInteger(maxEditLength) || maxEditLength < 0) {
    throw new RangeError('Context patch maxEditLength must be a nonnegative safe integer');
  }
  return { timeout, maxEditLength };
}

/** Each edit starts at a Unicode code-point offset in the unchanged baseline. */
export function textEdits(previousText, nextText, options) {
  if (typeof previousText !== 'string' || typeof nextText !== 'string') {
    throw new TypeError('Context patch text must be a string');
  }
  const limits = diffLimits(options);
  if (previousText === nextText) return [];
  const changes = diffChars(previousText, nextText, limits);
  if (!changes) {
    throw new ContextPatchError('Context patch computation exceeded its timeout or edit-distance limit', 'CONTEXT_PATCH_LIMIT');
  }
  const edits = [];
  let offset = 0;
  let edit;
  for (const change of changes) {
    if (change.added || change.removed) {
      edit ??= { start: offset, removed: '', inserted: '' };
      if (change.added) edit.inserted += change.value;
      else {
        edit.removed += change.value;
        offset += change.count;
      }
    } else {
      if (edit) edits.push(edit);
      edit = undefined;
      offset += change.count;
    }
  }
  if (edit) edits.push(edit);
  return edits;
}

function sameSource(previous, next) {
  if (!isDeepStrictEqual(previous.key, next.key)) {
    throw new ContextPatchError('Context patch requires the same context key', 'CONTEXT_PATCH_SOURCE');
  }
  if (previous.value.type !== next.value.type) {
    throw new ContextPatchError('Context patch requires the same context value type', 'CONTEXT_PATCH_SOURCE');
  }
  if (!isDeepStrictEqual(Object.keys(previous.value.fields).sort(), Object.keys(next.value.fields).sort())) {
    throw new ContextPatchError('Context patch requires the same field schema', 'CONTEXT_PATCH_SOURCE');
  }
}

/** Native admission checks the schema, identity projections and reconstructed value. */
export function proposeContextPatch(previousSnapshot, nextSnapshot, options) {
  const next = nextSnapshot?.value;
  if (!next || typeof next !== 'object' || !next.fields || typeof next.fields !== 'object' || Array.isArray(next.fields)) {
    throw new TypeError('Context patch requires a context field record');
  }
  if (previousSnapshot) sameSource(previousSnapshot, nextSnapshot);
  const fields = Object.entries(next.fields).flatMap(([field, value]) => {
    if (typeof value !== 'string') throw new TypeError('Context fields must contain strings');
    const edits = previousSnapshot ? textEdits(previousSnapshot.value.fields[field], value, options) : [];
    return edits.length ? [{ field, edits }] : [];
  });
  return { type: 'field_edits', fields };
}
