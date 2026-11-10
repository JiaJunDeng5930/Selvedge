/** Native observations retain composition; the extracted editor chooses handling. */
export function keyObservation(event, editorComposing = false) {
  return { keyboard: event.key, composing: Boolean(event.isComposing), editor_composing: Boolean(editorComposing), key_code: event.keyCode,
    shift: Boolean(event.shiftKey), alt: Boolean(event.altKey),
    modified: Boolean(event.ctrlKey || event.metaKey) };
}

export function editorKeyboard(event, normalize, deliver, editorComposing = false) {
  const decision = normalize(keyObservation(event, editorComposing));
  if (decision.prevent_default) event.preventDefault();
  if (decision.submit) deliver();
}

/** Provider selection updates the current form. Work choices can leave their dialog. */
export function selectingRadioGroup(target) {
  return target.matches('button[role="radio"]')
    ? target.closest('[role="radiogroup"][data-semantic-key="settings-provider-options"]') : null;
}

/** A radio group takes one Tab stop. An unchecked group starts at its first choice. */
export function radioTabTargets(candidates, active) {
  const stops = new Map();
  for (const candidate of candidates) {
    const group = selectingRadioGroup(candidate);
    if (group && (!stops.has(group) || candidate.getAttribute('aria-checked') === 'true')) {
      stops.set(group, candidate);
    }
  }
  const targets = candidates.filter(candidate => {
    const group = selectingRadioGroup(candidate);
    return !group || stops.get(group) === candidate;
  });
  return { targets, current: stops.get(selectingRadioGroup(active)) ?? active };
}

/** Domain skill and dictation ranges use UTF-8 bytes; native selection uses UTF-16. */
export function applyByteSelection(node, start, end, direction = 'none', focus = true) {
  const bytes = new TextEncoder().encode(node.value);
  const offset = position => new TextDecoder('utf-8', { fatal: true }).decode(bytes.slice(0, Number(position))).length;
  if (focus) node.focus({ preventScroll: true });
  node.setSelectionRange(offset(start), offset(end), direction);
}
