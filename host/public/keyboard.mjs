import { bendValue, bendTag } from './bend-value.mjs';

/** Preserve native observations; the compiled editor owns key policy. */
export function editorKeyboard(event, normalize, deliver) {
  const decision = normalize(bendValue('browser/editor/MODEL.KeyObservation', {
    keyboard: event.key,
    composing: Boolean(event.isComposing),
    key_code: event.keyCode,
    shift: Boolean(event.shiftKey),
    alt: Boolean(event.altKey),
    modified: Boolean(event.ctrlKey || event.metaKey),
  }));
  if (decision.prevent_default) event.preventDefault();
  if (bendTag(decision.event) === 'Some') deliver(decision.event.value);
}
