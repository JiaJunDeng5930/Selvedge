/** Native observations retain composition; the extracted editor chooses handling. */
export function keyObservation(event) {
  return { keyboard: event.key, composing: Boolean(event.isComposing), key_code: event.keyCode,
    shift: Boolean(event.shiftKey), alt: Boolean(event.altKey),
    modified: Boolean(event.ctrlKey || event.metaKey) };
}

export function editorKeyboard(event, normalize, deliver) {
  const decision = normalize(keyObservation(event));
  if (decision.prevent_default) event.preventDefault();
  if (decision.submit) deliver();
}

/** Domain skill and dictation ranges use UTF-8 bytes; native selection uses UTF-16. */
export function applyByteSelection(node, start, end) {
  const bytes = new TextEncoder().encode(node.value);
  const offset = position => new TextDecoder('utf-8', { fatal: true }).decode(bytes.slice(0, Number(position))).length;
  node.focus({ preventScroll: true });
  node.setSelectionRange(offset(start), offset(end));
}
