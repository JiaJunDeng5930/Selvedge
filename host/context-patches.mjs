import { diffChars } from 'diff';

const DIFF_TIMEOUT_MS = 250;
const MAX_EDIT_LENGTH = 8192;

/** Each edit starts at a Unicode code-point offset in the unchanged baseline. */
function textEdits(previousText, nextText) {
  if (previousText === nextText) return [];
  const changes = diffChars(previousText, nextText, { timeout: DIFF_TIMEOUT_MS, maxEditLength: MAX_EDIT_LENGTH });
  // DEFENSE: A large edit to an external context file can exhaust diff's declared computation budget.
  if (!changes) {
    throw new Error('Context patch computation exceeded its timeout or edit-distance limit');
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
export function proposeContextPatch(previousSnapshot, nextSnapshot) {
  const next = nextSnapshot.value;
  const fields = Object.entries(next.fields).flatMap(([field, value]) => {
    const edits = previousSnapshot ? textEdits(previousSnapshot.value.fields[field], value) : [];
    return edits.length ? [{ field, edits }] : [];
  });
  return { type: 'field_edits', fields };
}
