import { bendValue, bendTag } from './bend-value.mjs';

/** Preserve native observations; the compiled editor owns key policy. */
export function keyObservation(event) {
  return bendValue('browser/editor/MODEL.KeyObservation', {
    keyboard: event.key,
    composing: Boolean(event.isComposing),
    key_code: event.keyCode,
    shift: Boolean(event.shiftKey),
    alt: Boolean(event.altKey),
    modified: Boolean(event.ctrlKey || event.metaKey),
  });
}

export function editorKeyboard(event, normalize, deliver) {
  const decision = normalize(keyObservation(event));
  if (decision.prevent_default) event.preventDefault();
  if (bendTag(decision.event) === 'Some') deliver(decision.event.value);
}


// DOM text selection uses UTF-16 offsets; Bend strings count Unicode scalars.
export function scalarSelection(node) {
  return bendValue('browser/controls/GEOMETRY.Selection', {
    start: BigInt(Array.from(node.value.slice(0, node.selectionStart)).length),
    end: BigInt(Array.from(node.value.slice(0, node.selectionEnd)).length),
    direction: node.selectionDirection ?? 'none',
  });
}

export function applyScalarSelection(node, selection) {
  const scalars = Array.from(node.value);
  const offset = index => scalars.slice(0, Number(index)).join('').length;
  node.focus({ preventScroll: true });
  node.setSelectionRange(offset(selection.start), offset(selection.end), selection.direction);
}
