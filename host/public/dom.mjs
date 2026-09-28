export function element(document, tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

export function setText(node, text) {
  if (node.textContent !== text) node.textContent = text;
}

const paths = {
  new: ['M12 4H5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h13a2 2 0 0 0 2-2v-7', 'm15 3 6 6', 'm9 15 2.5-6.5L18 2l4 4-6.5 6.5L9 15Z'],
  panel: ['M4 4h16v16H4z', 'M15 4v16'],
  up: ['M12 19V5', 'm5 12 7-7 7 7'],
  down: ['M12 5v14', 'm5 12 7 7 7-7'],
  chevron: ['m8 10 4 4 4-4'],
  settings: ['M4 7h16M4 17h16', 'M8 4v6M16 14v6'],
  more: ['M5 12h.01M12 12h.01M19 12h.01'],
  close: ['m6 6 12 12M18 6 6 18'],
  check: ['m5 12 4 4L19 6'],
  activity: ['m4 12 4-6 8 12 4-6'],
};

export function icon(document, name) {
  if (!paths[name]) throw new TypeError(`Unknown icon: ${name}`);
  const node = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  for (const [key, value] of Object.entries({ viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor',
    'stroke-width': '1.5', 'stroke-linecap': 'round', 'stroke-linejoin': 'round',
    'aria-hidden': 'true', focusable: 'false', class: 'icon' })) node.setAttribute(key, value);
  for (const d of paths[name]) {
    const path = document.createElementNS(node.namespaceURI, 'path');
    path.setAttribute('d', d); node.append(path);
  }
  return node;
}

// Splice keyed children without detaching editors, selections, or closed
// Markdown nodes. Identity, not a new HTML string, is the rendering contract.
export function reconcile(parent, children) {
  const expected = new Set(children);
  for (const child of [...parent.childNodes]) if (!expected.has(child)) child.remove();
  for (let i = 0; i < children.length; i++) {
    if (parent.childNodes[i] !== children[i]) parent.insertBefore(children[i], parent.childNodes[i] ?? null);
  }
}
