import * as smd from './vendor/streaming-markdown.mjs';

const displayJobs = new Map();
let displayId = 0;
let displayFrame = null;
function paint(time) {
  displayFrame = null;
  const start = performance.now();
  // A history page can introduce many Markdown instances at once. They share
  // a main-thread budget instead of each claiming a whole animation frame.
  for (const [id, callback] of [...displayJobs]) {
    if (performance.now() - start >= 6) break;
    if (displayJobs.delete(id)) callback(time);
  }
  if (displayJobs.size && displayFrame === null) displayFrame = requestAnimationFrame(paint);
}
function scheduleDisplay(callback) {
  const id = ++displayId;
  displayJobs.set(id, callback);
  if (displayFrame === null) displayFrame = requestAnimationFrame(paint);
  return id;
}
function cancelDisplay(id) {
  displayJobs.delete(id);
  if (!displayJobs.size && displayFrame !== null) { cancelAnimationFrame(displayFrame); displayFrame = null; }
}

// Target text, visible cursor, and parser stack are deliberately independent.
// The parser sees each character once; closed DOM nodes never get reparsed.
export class PacedText {
  constructor(write, end, { frame = scheduleDisplay, cancel = cancelDisplay, smooth = true } = {}) {
    Object.assign(this, { write, end, frame, cancel, smooth, target: '', visible: 0, done: false, stopped: false, scheduled: null, last: -Infinity });
    this.metrics = { characters: 0, batches: 0, largestBatch: 0, maxParseMs: 0 };
  }
  append(text) {
    if (this.done || this.stopped) return;
    if (typeof text !== 'string') throw new TypeError('Markdown input must be text');
    if (this.target.length + text.length > 4 * 1024 * 1024) throw new RangeError('Markdown text exceeds the display limit');
    this.target += text;
    this.schedule();
  }
  finish() { this.done = true; this.schedule(); }
  schedule() {
    if (!this.stopped && this.scheduled === null) this.scheduled = this.frame(time => this.tick(time));
  }
  tick(time) {
    this.scheduled = null;
    if (this.stopped) return;
    if (time - this.last < 32) { this.schedule(); return; }
    this.last = time;
    const backlog = this.target.length - this.visible;
    const size = this.smooth && !this.done ? Math.max(24, Math.ceil(backlog / 5)) : 4096;
    let end = Math.min(this.target.length, this.visible + Math.min(4096, size));
    // Keep surrogate pairs intact, including a pair split between arrivals.
    if (end > this.visible && /[\uD800-\uDBFF]/.test(this.target[end - 1]) && (end < this.target.length || !this.done)) end--;
    if (end > this.visible) {
      const chunk = this.target.slice(this.visible, end);
      this.metrics.characters += chunk.length;
      this.metrics.batches++;
      this.metrics.largestBatch = Math.max(this.metrics.largestBatch, chunk.length);
      const start = performance.now();
      this.write(chunk);
      this.metrics.maxParseMs = Math.max(this.metrics.maxParseMs, performance.now() - start);
      this.visible = end;
    }
    if (this.visible < this.target.length) this.schedule();
    else if (this.done) {
      this.stopped = true;
      const start = performance.now(); this.end();
      this.metrics.maxParseMs = Math.max(this.metrics.maxParseMs, performance.now() - start);
    }
  }
  dispose() {
    this.stopped = true;
    if (this.scheduled !== null) this.cancel(this.scheduled);
    this.scheduled = null;
  }
}

export function safeHref(value) {
  if (typeof value !== 'string' || /[\u0000-\u0020\u007f\\]/.test(value)) return null;
  if (value.startsWith('#')) return value;
  try {
    const url = new URL(value);
    return ['https:', 'http:', 'mailto:'].includes(url.protocol) ? url.href : null;
  } catch { return null; }
}

let worker;
let serial = 0;
const jobs = new Map();
function resetFormatter() {
  worker?.terminate(); worker = null;
  for (const job of jobs.values()) clearTimeout(job.timer);
  jobs.clear();
}
function decorate(node, kind, text, language, alive) {
  // Expensive parsing runs off the main thread and only after a token closes.
  // Very large code/math stays selectable plain text, never a blocking job.
  if (text.length > (kind === 'code' ? 24000 : 4000) || jobs.size >= 64 || typeof Worker === 'undefined') return;
  const idle = globalThis.requestIdleCallback ?? (callback => setTimeout(callback, 0));
  idle(() => {
    if (!alive() || jobs.size >= 64) return;
    try {
      if (!worker) {
        worker = new Worker(new URL('./markdown-worker.mjs', import.meta.url), { type: 'module' });
        worker.onmessage = ({ data }) => {
          const job = jobs.get(data.id);
          jobs.delete(data.id);
          clearTimeout(job?.timer);
          if (job && typeof data.markup === 'string' && data.markup.length <= 512 * 1024) job(data.markup);
        };
        worker.onerror = resetFormatter;
      }
      const id = ++serial;
      jobs.set(id, markup => {
        if (!alive() || !node.isConnected) return;
        const selection = node.ownerDocument.getSelection();
        if (selection?.rangeCount && selection.getRangeAt(0).intersectsNode(node)) return;
        // Only trusted formatter output is parsed, never raw model HTML. A
        // second allowlist keeps formatter output a non-interactive fragment.
        const parsed = new DOMParser().parseFromString(markup, 'text/html');
        const allowed = new Set(['span', 'math', 'semantics', 'annotation', 'mrow', 'mi', 'mo', 'mn', 'ms', 'mtext', 'mspace', 'msup', 'msub', 'msubsup', 'mfrac', 'msqrt', 'mroot', 'mover', 'munder', 'munderover', 'mtable', 'mtr', 'mtd', 'mpadded', 'mstyle', 'menclose', 'mphantom']);
        const clean = source => {
          if (source.nodeType === 3) return node.ownerDocument.createTextNode(source.textContent);
          if (source.nodeType !== 1 || !allowed.has(source.localName)) return node.ownerDocument.createTextNode(source.textContent ?? '');
          const result = node.ownerDocument.createElementNS(source.namespaceURI, source.localName);
          for (const attribute of source.attributes) {
            if (['class', 'display', 'encoding', 'mathvariant', 'stretchy', 'fence', 'separator', 'accent', 'accentunder', 'columnalign', 'rowalign', 'columnspacing', 'rowspacing', 'linethickness', 'scriptlevel', 'displaystyle', 'width', 'height', 'depth', 'lspace', 'rspace', 'minsize', 'maxsize'].includes(attribute.name)) result.setAttribute(attribute.name, attribute.value);
          }
          for (const child of source.childNodes) result.append(clean(child));
          return result;
        };
        node.replaceChildren(...[...parsed.body.childNodes].map(clean));
        node.dataset.decorated = kind;
      });
      jobs.get(id).timer = setTimeout(resetFormatter, 5000);
      worker.postMessage({ id, kind, text, language });
    } catch { /* Plain text is the intentional formatter-failure fallback. */ }
  }, { timeout: 500 });
}

const tags = new Map([
  [smd.PARAGRAPH, 'p'], [smd.BLOCKQUOTE, 'blockquote'], [smd.CODE_INLINE, 'code'],
  [smd.ITALIC_AST, 'em'], [smd.ITALIC_UND, 'em'], [smd.STRONG_AST, 'strong'], [smd.STRONG_UND, 'strong'],
  [smd.STRIKE, 's'], [smd.LINK, 'a'], [smd.RAW_URL, 'a'], [smd.IMAGE, 'a'],
  [smd.LINE_BREAK, 'br'], [smd.RULE, 'hr'], [smd.LIST_UNORDERED, 'ul'], [smd.LIST_ORDERED, 'ol'],
  [smd.LIST_ITEM, 'li'], [smd.CHECKBOX, 'input'], [smd.TABLE, 'table'], [smd.TABLE_ROW, 'tr'],
  [smd.TABLE_CELL, 'td'], [smd.EQUATION_BLOCK, 'div'], [smd.EQUATION_INLINE, 'span'],
]);
for (let i = 0; i < 6; i++) tags.set(smd.HEADING_1 + i, `h${i + 1}`);

export class Markdown {
  constructor(root, options = {}) {
    this.root = root;
    this.disposed = false;
    this.stableBlocks = 0;
    let ordinal = 0n;
    const codeSources = new Map();
    const reportCode = () => {
      for (const [node, identity] of codeSources) {
        const text = node.textContent;
        if (identity.text !== text) { identity.text = text; options.codeSource?.(identity.ordinal, text); }
      }
    };
    const document = root.ownerDocument;
    const stack = [{ node: root, type: smd.DOCUMENT }];
    const close = () => {
      if (stack.length <= 1) return;
      const entry = stack.pop();
      delete entry.node.dataset.pending;
      if (stack.length === 1) { entry.node.dataset.stable = 'true'; this.stableBlocks++; }
      const kind = [smd.CODE_BLOCK, smd.CODE_FENCE].includes(entry.type) ? 'code'
        : [smd.EQUATION_BLOCK, smd.EQUATION_INLINE].includes(entry.type) ? 'math' : null;
      if (kind) decorate(entry.node, kind, entry.node.textContent, entry.node.dataset.language, () => !this.disposed);
    };
    const sink = {
      data: null,
      add_token: (_, type) => {
        if (type === smd.DOCUMENT) return;
        let parent = stack.at(-1).node;
        let node;
        if ([smd.CODE_BLOCK, smd.CODE_FENCE].includes(type)) {
          const block = document.createElement('div'); block.className = 'code-block';
          const toolbar = document.createElement('div'); toolbar.className = 'code-toolbar';
          const pre = document.createElement('pre'); node = document.createElement('code');
          const identity = ordinal++;
          const key = options.codeKey?.(identity);
          if (key) {
            options.target?.(`${key}/toolbar`, toolbar);
            options.target?.(`${key}/code`, node);
          }
          codeSources.set(node, { ordinal: identity, text: null });
          pre.append(node); block.append(toolbar, pre); parent.append(block);
        } else {
          node = document.createElement(tags.get(type) ?? 'span');
          if (type === smd.TABLE) {
            const scroll = document.createElement('div'); scroll.className = 'table-scroll'; parent.append(scroll); parent = scroll;
          }
          if (type === smd.CHECKBOX) { node.type = 'checkbox'; node.disabled = true; }
          if (type === smd.IMAGE) { node.className = 'markdown-image-link'; node.setAttribute('aria-label', 'Image link (not loaded automatically)'); }
          if ([smd.EQUATION_BLOCK, smd.EQUATION_INLINE].includes(type)) { node.className = 'math-source'; node.dataset.language = type === smd.EQUATION_BLOCK ? 'display' : 'inline'; }
          parent.append(node);
        }
        node.dataset.pending = 'true';
        stack.push({ node, type });
      },
      end_token: close,
      add_text: (_, text) => {
        const node = stack.at(-1).node;
        // Append to the same text node, preserving selection and bounding the
        // DOM-node count independently of upstream token chunking.
        if (node.lastChild?.nodeType === 3) node.lastChild.appendData(text);
        else node.append(document.createTextNode(text));
      },
      set_attr: (_, attr, value) => {
        const node = stack.at(-1).node;
        if ([smd.HREF, smd.SRC].includes(attr)) {
          const href = safeHref(value);
          if (href) { node.setAttribute('href', href); node.setAttribute('target', '_blank'); node.setAttribute('rel', 'noopener noreferrer'); }
        } else if (attr === smd.LANG) {
          node.dataset.language = value.split(/\s/)[0].slice(0, 40);
        } else if (attr === smd.CHECKED) node.checked = true;
        else if (attr === smd.START && /^\d{1,9}$/.test(value)) node.setAttribute('start', value);
      },
    };
    const parser = smd.parser(sink);
    this.buffer = new PacedText(chunk => { smd.parser_write(parser, chunk); reportCode(); options.onChange?.(); }, () => {
      smd.parser_end(parser);
      while (stack.length > 1) close();
      reportCode(); options.onChange?.();
    }, options);
  }
  get text() { return this.buffer.target; }
  append(text) { this.buffer.append(text); }
  finish() { this.buffer.finish(); }
  dispose() { this.disposed = true; this.buffer.dispose(); }
}
