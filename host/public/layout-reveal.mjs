// The extracted model marks the native targets whose layout should keep them exposed.
// Scrolling alone does not change this signature or move keyboard focus.
export function revealInScrollport(node) {
  node.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'instant' });
}
export function revealAndFocus(node) {
  revealInScrollport(node);
  node.focus({ preventScroll: true });
}
export function createLayoutRevealer(root, activeModal) {
  let previous = new Map();
  const coordinate = value => Math.round(value * 100) / 100;
  return function revealLayoutTargets() {
    const current = new Map();
    const modal = activeModal();
    for (const node of root.querySelectorAll('[data-reveal-on-layout="true"]')) {
      if (modal && !modal.contains(node)) {
        // A foreground native dialog makes the background inert without adding an inert attribute.
        if (previous.has(node)) current.set(node, previous.get(node));
        continue;
      }
      if (!node.getClientRects().length || node.closest('[aria-hidden="true"],[inert]')
        || getComputedStyle(node).visibility === 'hidden') continue;
      const box = node.getBoundingClientRect();
      const ports = [];
      const geometry = [box.width, box.height];
      let scrollLeft = 0;
      let scrollTop = 0;
      for (let parent = node.parentElement; parent; parent = parent.parentElement) {
        scrollLeft += parent.scrollLeft;
        scrollTop += parent.scrollTop;
        const style = getComputedStyle(parent);
        if (![style.overflowX, style.overflowY].some(value => /^(auto|scroll|overlay)$/.test(value))) continue;
        const bounds = parent.getBoundingClientRect();
        ports.push(parent);
        geometry.push(parent.clientWidth, parent.clientHeight,
          coordinate(box.left - bounds.left + scrollLeft),
          coordinate(box.top - bounds.top + scrollTop));
      }
      if (!ports.length) geometry.push(document.documentElement.clientWidth, document.documentElement.clientHeight);
      const signature = JSON.stringify(geometry);
      const before = previous.get(node);
      if (!before || before.signature !== signature || before.ports.length !== ports.length
        || ports.some((port, index) => port !== before.ports[index])) {
        revealInScrollport(node);
      }
      current.set(node, { signature, ports });
    }
    previous = current;
  };
}

// The model places the same repair beside its field and in the fixed actions.
// Use the inline placement only while both the field and its repair fit.
export function createEditorRepairPlacement(activeModal) {
  const placement = 'data-editor-repair-inline';
  let current;
  function dispose() {
    if (!current) return;
    current.observer.disconnect();
    current.dialog.removeAttribute(placement);
    current = undefined;
  }
  function refresh() {
    const dialog = activeModal();
    const body = dialog?.querySelector(':scope > form[data-semantic-key="editor"] > [data-surface-role="dialog-body"]');
    const inline = body?.querySelector('[data-semantic-key="property-repair"]');
    // The editor publishes the field immediately before its repair.
    const field = inline?.previousElementSibling;
    const footer = body?.nextElementSibling?.querySelector('[data-semantic-key="editor-commit-reason"]');
    if (current?.dialog === dialog && current?.inline === inline && current?.field === field && current?.footer === footer)
      return;
    dispose();
    if (!field || !footer) return;

    const visible = new Set();
    const observer = new IntersectionObserver(entries => {
      // DEFENSE: A queued receipt from a dismissed or replaced repair cannot
      // change the placement in the current editor.
      if (current?.observer !== observer) return;
      for (const entry of entries) {
        if (entry.isIntersecting && entry.intersectionRatio === 1) visible.add(entry.target);
        else visible.delete(entry.target);
      }
      dialog.toggleAttribute(placement, visible.has(field) && visible.has(inline));
    }, { root: body, threshold: 1 });
    current = { dialog, inline, field, footer, observer };
    observer.observe(field);
    observer.observe(inline);
  }
  return { refresh, dispose };
}
