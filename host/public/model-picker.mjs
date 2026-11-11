/** Paint native range previews without publishing a draft on every pointer move. */
export function installModelPickerPreview(surface) {
  const previews = new WeakMap();
  const gestures = new WeakMap();
  const pointers = new Map();
  surface.addEventListener('pointerdown', event => {
    const input = event.target;
    if (!input.matches?.('input[data-model-effort-range]')) return;
    const gesture = { input, options: input.dataset.effortLabels };
    gestures.set(input, gesture);
    pointers.set(event.pointerId, gesture);
  }, true);
  const release = event => {
    const gesture = pointers.get(event.pointerId);
    if (!gesture) return;
    pointers.delete(event.pointerId);
    // A native change can follow pointerup within the same task.
    setTimeout(() => {
      if (gestures.get(gesture.input) === gesture) gestures.delete(gesture.input);
    }, 0);
  };
  const window = surface.ownerDocument.defaultView;
  window.addEventListener('pointerup', release, true);
  window.addEventListener('pointercancel', release, true);
  surface.addEventListener('input', event => {
    const input = event.target;
    if (!input.matches?.('input[data-model-effort-range]')) return;
    let preview = previews.get(input);
    if (!preview) {
      const track = input.parentElement;
      const effort = input.closest('dialog').querySelector('[data-semantic-key="current-effort"]');
      preview = { track, effort, source: input.dataset.effortLabels,
        labels: JSON.parse(input.dataset.effortLabels) };
      previews.set(input, preview);
    }
    if (preview.source !== input.dataset.effortLabels) {
      preview.source = input.dataset.effortLabels;
      preview.labels = JSON.parse(preview.source);
    }
    const label = preview.labels[input.valueAsNumber];
    preview.track.style.setProperty('--effort-preview', input.value);
    if (preview.effort) preview.effort.dataset.effortPreview = label;
    input.setAttribute('aria-valuetext', label);
  });
  const clear = event => {
    const input = event.target;
    const preview = previews.get(input);
    if (!preview) return;
    previews.delete(input);
    preview.track.style.removeProperty('--effort-preview');
    preview.effort?.removeAttribute('data-effort-preview');
    const committedIndex = () => preview.track.style.getPropertyValue('--effort-index');
    input.setAttribute('aria-valuetext', JSON.parse(input.dataset.effortLabels)[Number(committedIndex())] ?? '');
    // DEFENSE: A canceled drag or rejected change can leave the native thumb at
    // its preview position. Restore the most recent published value after dispatch.
    queueMicrotask(() => {
      if (input.isConnected && !previews.has(input) && input.value !== committedIndex())
        input.value = committedIndex();
    });
  };
  surface.addEventListener('change', event => {
    const input = event.target;
    const gesture = gestures.get(input);
    if (!gesture) return;
    gestures.delete(input);
    // DEFENSE: An assessment can insert an effort while the thumb is held.
    // The old index must not be submitted against the new list of options.
    if (gesture.options !== input.dataset.effortLabels) {
      event.stopPropagation();
      clear(event);
      input.value = input.parentElement.style.getPropertyValue('--effort-index');
    }
  }, true);
  // The native binding reads the new value at the target before preview
  // cleanup. Trusted events can run microtasks between their listeners.
  surface.addEventListener('change', clear);
  surface.addEventListener('pointercancel', clear);
}
