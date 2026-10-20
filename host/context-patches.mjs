import { diffChars } from 'diff';

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
  return { timeout, maxEditLength };
}

/** Each edit starts at a Unicode code-point offset in the unchanged baseline. */
export function textEdits(previousText, nextText, options) {
  const limits = diffLimits(options);
  if (previousText === nextText) return [];
  const changes = diffChars(previousText, nextText, limits);
  // DEFENSE: A large edit to an external context file can exhaust diff's declared computation budget.
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

/** Native admission checks the schema, identity projections and reconstructed value. */
export function proposeContextPatch(previousSnapshot, nextSnapshot, options) {
  const next = nextSnapshot.value;
  const fields = Object.entries(next.fields).flatMap(([field, value]) => {
    const edits = previousSnapshot ? textEdits(previousSnapshot.value.fields[field], value, options) : [];
    return edits.length ? [{ field, edits }] : [];
  });
  return { type: 'field_edits', fields };
}
