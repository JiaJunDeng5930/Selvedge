const labelSelector = '[data-overflow-label]';
const contentSelector = ':scope > [data-single-line-content]';

export function observeSingleLineLabels(surface) {
  const observed = new Map();
  const observer = new ResizeObserver(entries => {
    const labels = new Set(entries.map(({ target }) =>
      target.matches(labelSelector) ? target : target.parentElement));
    for (const label of labels) {
      const content = observed.get(label);
      if (!content) continue;
      const width = label.clientWidth;
      const distance = content.offsetWidth - width;
      const clipped = width > 0 && distance > 0;
      label.toggleAttribute('data-label-clipped', clipped);
      if (clipped) {
        content.style.setProperty('--label-travel', `${distance}px`);
        content.style.setProperty('--label-duration', `${distance / 42 + 1}s`);
      }
      if (!label.closest('button, summary, a') && label.hasAttribute('tabindex')) {
        label.tabIndex = clipped ? 0 : -1;
      }
    }
  });

  const mutations = new MutationObserver(records => {
    const labels = new Set();
    for (const record of records) {
      if (record.type === 'attributes' || record.target.matches?.(labelSelector)) labels.add(record.target);
      for (const node of [...record.addedNodes, ...record.removedNodes]) {
        if (node.nodeType !== Node.ELEMENT_NODE) continue;
        if (node.matches(labelSelector)) labels.add(node);
        for (const label of node.querySelectorAll(labelSelector)) labels.add(label);
      }
    }
    for (const label of labels) {
      const previous = observed.get(label) ?? null;
      const content = surface.contains(label) && label.matches(labelSelector) ? label.querySelector(contentSelector) : null;
      if (previous === content) continue;
      if (previous) {
        observer.unobserve(previous);
        observed.delete(label);
      }
      if (content) {
        observer.observe(label);
        observer.observe(content);
        observed.set(label, content);
      } else {
        observer.unobserve(label);
      }
    }
  });
  mutations.observe(surface, { childList: true, subtree: true, attributeFilter: ['data-overflow-label'] });

  function updateScroll(event) {
    const label = event.target;
    if (label.matches?.(labelSelector)) {
      label.toggleAttribute('data-label-scrolled', label.scrollLeft !== 0);
    }
  }
  surface.addEventListener('scroll', updateScroll, { capture: true, passive: true });

  return () => {
    mutations.disconnect();
    observer.disconnect();
    surface.removeEventListener('scroll', updateScroll, true);
    observed.clear();
  };
}
