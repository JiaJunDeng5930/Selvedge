// Search chooses the message and supplies its normalized query. This walk only
// observes where that text is painted in the message's Markdown surface.
const excluded = '[hidden],[inert],[aria-hidden="true"],.interactive-markdown-target,.code-toolbar,code[data-language="selvedge-ui"]';
const textBlock = 'p,h1,h2,h3,h4,h5,h6,li,blockquote,pre,td,th,.math-source';
const foldAscii = text => text.replace(/[A-Z]/g, letter => letter.toLowerCase());

function boundary(parts, offset, end) {
  for (const part of parts) {
    if (offset < part.length || end && offset === part.length) return [part.node, part.start + offset];
    offset -= part.length;
  }
}

export function firstRangeRect(range) {
  return Array.from(range.getClientRects()).find(rect => rect.width > 0 && rect.height > 0);
}

export function* findHistoryRange(body, query) {
  if (!query) return null;
  const document = body.ownerDocument;
  const walker = document.createTreeWalker(body, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
    acceptNode: node => node.nodeType === Node.ELEMENT_NODE && node.matches(excluded)
      ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
  });
  let block, tail = '', previous = [];
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (node.nodeType !== Node.TEXT_NODE) {
      if (node.tagName === 'BR') { tail = ''; previous = []; }
      yield;
      continue;
    }
    const containingBlock = node.parentElement.closest(textBlock) ?? body;
    if (block !== containingBlock) { block = containingBlock; tail = ''; previous = []; }
    for (let start = 0; start < node.length; start += 4096) {
      const current = foldAscii(node.substringData(start, 4096));
      const text = tail + current;
      const parts = [...previous, { node, start, length: current.length }];
      for (let match = text.indexOf(query); match >= 0; match = text.indexOf(query, match + 1)) {
        const range = document.createRange();
        range.setStart(...boundary(parts, match, false));
        range.setEnd(...boundary(parts, match + query.length, true));
        const owner = range.startContainer.parentElement;
        if (getComputedStyle(owner).visibility === 'visible' && firstRangeRect(range)) return range;
        yield;
      }
      // Only a possible cross-node prefix is needed on the next turn.
      let skip = Math.max(0, text.length - query.length + 1);
      tail = text.slice(skip);
      previous = [];
      for (const part of parts) {
        if (skip >= part.length) skip -= part.length;
        else {
          previous.push({ node: part.node, start: part.start + skip, length: part.length - skip });
          skip = 0;
        }
      }
      yield;
    }
  }
  return null;
}
