/** Paint native range previews without publishing a draft on every pointer move. */
export function installModelPickerPreview(surface) {
  const previews = new WeakMap();
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
  // The native binding reads the new value at the target before preview
  // cleanup. Trusted events can run microtasks between their listeners.
  surface.addEventListener('change', clear);
  surface.addEventListener('pointercancel', clear);
}
