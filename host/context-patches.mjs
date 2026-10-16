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
  if (previous.value.type === 'skill_information' && previous.value.path !== next.value.path) {
    throw new ContextPatchError('Context patch requires the same skill path', 'CONTEXT_PATCH_SOURCE');
  }
}

/** Propose only the changed fields; native admission verifies the resulting value. */
export function proposeContextPatch(previousSnapshot, nextSnapshot, options) {
  const next = nextSnapshot?.value;
  if (!next || typeof next !== 'object') throw new TypeError('Context patch requires a next context snapshot');
  if (previousSnapshot) sameSource(previousSnapshot, nextSnapshot);
  switch (next.type) {
    case 'instruction':
    case 'project_guidance':
      return { type: 'text_edits', edits: previousSnapshot ? textEdits(previousSnapshot.value.content, next.content, options) : [] };
    case 'skill_information':
      return {
        type: 'skill_edits',
        name: previousSnapshot ? textEdits(previousSnapshot.value.name, next.name, options) : [],
        description: previousSnapshot ? textEdits(previousSnapshot.value.description, next.description, options) : [],
      };
    default:
      throw new TypeError('Context patch has an unsupported context value type');
  }
}
