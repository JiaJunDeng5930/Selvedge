// Bend marks the native targets whose layout should keep them exposed.
// Scrolling alone does not change this signature or move keyboard focus.
export function createLayoutRevealer(root) {
  let previous = new Map();
  const coordinate = value => Math.round(value * 100) / 100;
  return function revealLayoutTargets() {
    const current = new Map();
    for (const node of root.querySelectorAll('[data-reveal-on-layout="true"]')) {
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
        node.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'instant' });
      }
      current.set(node, { signature, ports });
    }
    previous = current;
  };
}
