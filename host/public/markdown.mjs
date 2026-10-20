import { boundary } from './model-boundary.mjs';
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
export function scheduleDisplay(callback) {
  const id = ++displayId;
  displayJobs.set(id, callback);
  if (displayFrame === null) displayFrame = requestAnimationFrame(paint);
  return id;
}
export function cancelDisplay(id) {
  displayJobs.delete(id);
  if (!displayJobs.size && displayFrame !== null) { cancelAnimationFrame(displayFrame); displayFrame = null; }
}

// Target text, visible cursor, and parser stack are deliberately independent.
// The parser sees each character once; closed DOM nodes never get reparsed.
export class PacedText {
  constructor(write, end, { frame = scheduleDisplay, cancel = cancelDisplay, smooth = true } = {}) {
    Object.assign(this, { write, end, frame, cancel, smooth, target: '', visible: 0, done: false, stopped: false, scheduled: null, last: -Infinity });
    this.finished = null;
    this.completion = new Promise(resolve => { this.resolveCompletion = resolve; });
    this.prefixWaiters = new Set();
    this.metrics = { characters: 0, batches: 0, largestBatch: 0, maxParseMs: 0 };
  }
  append(text) {
    if (this.done || this.stopped) return;
    // DEFENSE: Streamed model output can exceed the 4 MiB Markdown display budget.
    if (this.target.length + text.length > 4 * 1024 * 1024) throw new RangeError('Markdown text exceeds the display limit');
    this.target += text;
    this.schedule();
  }
  finish() { this.done = true; this.schedule(); }
  whenCaughtUp(length = this.target.length) {
    if (this.visible >= length) return Promise.resolve(!this.stopped || this.finished === true);
    if (this.stopped) return Promise.resolve(false);
    return new Promise(resolve => this.prefixWaiters.add({ length, resolve }));
  }
  settlePrefixes(alive = true) {
    for (const waiter of this.prefixWaiters) {
      if (!alive || this.visible >= waiter.length) {
        this.prefixWaiters.delete(waiter); waiter.resolve(alive);
      }
    }
  }
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
      this.settlePrefixes();
    }
    if (this.visible < this.target.length) this.schedule();
    else if (this.done) {
      this.stopped = true;
      const start = performance.now(); this.end();
      this.metrics.maxParseMs = Math.max(this.metrics.maxParseMs, performance.now() - start);
      if (this.finished === null) { this.finished = true; this.resolveCompletion(true); }
      this.settlePrefixes();
    }
  }
  whenFinished() { return this.completion; }
  dispose() {
    this.stopped = true;
    if (this.scheduled !== null) this.cancel(this.scheduled);
    this.scheduled = null;
    if (this.finished === null) { this.finished = false; this.resolveCompletion(false); }
    this.settlePrefixes(false);
  }
}

export function safeHref(value) {
  let observation = { parsed: false };
  try {
    const url = new URL(value);
    observation = { parsed: true, href: url.href, scheme: url.protocol,
      username: url.username, password: url.password, hash: url.hash };
  } catch (error) {
    // DEFENSE: Markdown links may be relative, fragments or malformed URLs; Bend admits only its allowed navigation forms.
    if (!(error instanceof TypeError)) throw error;
  }
  return boundary('browser.link', { raw: value, observation });
}

const HTML_NAMESPACE = 'http://www.w3.org/1999/xhtml';
const MATHML_NAMESPACE = 'http://www.w3.org/1998/Math/MathML';
const FORMATTER_MATHML_ELEMENTS = new Set(['math', 'semantics', 'annotation', 'mrow', 'mi', 'mo', 'mn', 'ms', 'mtext', 'mspace', 'msup', 'msub', 'msubsup', 'mfrac', 'msqrt', 'mroot', 'mover', 'munder', 'munderover', 'mtable', 'mtr', 'mtd', 'mpadded', 'mstyle', 'menclose', 'mphantom']);
const FORMATTER_HTML_ATTRIBUTES = new Set(['class']);
const FORMATTER_MATHML_ATTRIBUTES = new Set(['class', 'display', 'encoding', 'mathvariant', 'stretchy', 'fence', 'separator', 'accent', 'accentunder', 'columnalign', 'rowalign', 'columnspacing', 'rowspacing', 'linethickness', 'scriptlevel', 'displaystyle', 'notation', 'width', 'height', 'depth', 'lspace', 'rspace', 'minsize', 'maxsize', 'mathcolor', 'mathbackground', 'voffset', 'linebreak', 'columnlines', 'rowlines', 'largeop', 'mathsize']);
const FORMATTER_MATHML_STYLE_PROPERTIES = ['text-shadow', 'border'];
const UNSAFE_FORMATTER_STYLE_VALUE = /url\s*\(|expression\s*\(|var\s*\(|@|\\|[\u0000-\u001f\u007f]/i;

function copyMathMLStyle(source, result, document) {
  // KaTeX emits these two presentation properties; other CSS stays outside the fragment boundary.
  const parsedStyle = document.createElement('span').style;
  parsedStyle.cssText = source.getAttribute('style') ?? '';
  for (const property of FORMATTER_MATHML_STYLE_PROPERTIES) {
    const value = parsedStyle.getPropertyValue(property);
    // DEFENSE: Formatter CSS derived from model math must not introduce resource URLs, indirection or executable CSS.
    if (value && !UNSAFE_FORMATTER_STYLE_VALUE.test(value)) result.style.setProperty(property, value);
  }
}

function cleanFormatterFragment(source, document) {
  if (source.nodeType === 3) return document.createTextNode(source.textContent);
  const mathml = source.namespaceURI === MATHML_NAMESPACE;
  const allowed = source.nodeType === 1 && (mathml
    ? FORMATTER_MATHML_ELEMENTS.has(source.localName)
    : source.namespaceURI === HTML_NAMESPACE && source.localName === 'span');
  // DEFENSE: Formatter HTML is derived from model text; discard elements outside the non-interactive MathML/span allowlist.
  if (!allowed) return document.createTextNode(source.textContent ?? '');
  const result = document.createElementNS(source.namespaceURI, source.localName);
  const attributes = mathml ? FORMATTER_MATHML_ATTRIBUTES : FORMATTER_HTML_ATTRIBUTES;
  for (const attribute of source.attributes) {
    if (mathml && attribute.name === 'xmlns' && attribute.value === MATHML_NAMESPACE
        && (attribute.namespaceURI === null || attribute.namespaceURI === 'http://www.w3.org/2000/xmlns/')) {
      result.setAttribute('xmlns', MATHML_NAMESPACE);
      continue;
    }
    // DEFENSE: Namespaced formatter attributes must not bypass the non-interactive attribute allowlist.
    if (attribute.namespaceURI !== null) continue;
    // DEFENSE: Formatting output must not install event handlers, links or attributes outside the permitted presentation vocabulary.
    if (attributes.has(attribute.name)) result.setAttribute(attribute.name, attribute.value);
  }
  if (mathml) copyMathMLStyle(source, result, document);
  for (const child of source.childNodes) result.append(cleanFormatterFragment(child, document));
  return result;
}

let worker;
let serial = 0;
const jobs = new Map();
function resetFormatter() {
  const formatter = worker;
  worker = null;
  for (const job of [...jobs.values()]) job.settle(job.alive());
  formatter?.terminate();
}
function decorate(node, kind, text, language, alive, signal, onChange) {
  // Account for the idle stage as well as worker work so owner completion
  // cannot run ahead of formatting that has not entered the global queue yet.
  return new Promise(resolve => {
    let settled = false;
    let idleId = null;
    let jobId = null;
    let timer = null;
    // DEFENSE: Safari does not expose requestIdleCallback; schedule optional formatting on a timer in that browser.
    const nativeIdle = typeof globalThis.requestIdleCallback === 'function';
    const idle = nativeIdle ? globalThis.requestIdleCallback.bind(globalThis) : callback => setTimeout(callback, 0);
    const cancelIdle = () => {
      if (idleId === null) return;
      if (nativeIdle) globalThis.cancelIdleCallback(idleId);
      else clearTimeout(idleId);
      idleId = null;
    };
    const settle = outcome => {
      if (settled) return;
      settled = true;
      cancelIdle();
      clearTimeout(timer);
      if (jobId !== null) jobs.delete(jobId);
      signal.removeEventListener('abort', cancelled);
      resolve(outcome);
    };
    const cancelled = () => settle(false);
    signal.addEventListener('abort', cancelled, { once: true });
    if (!alive() || signal.aborted) { settle(false); return; }
    // DEFENSE: Model-authored code/math may be large or numerous; cap worker work while retaining selectable source text.
    if (text.length > (kind === 'code' ? 24000 : 4000) || jobs.size >= 64) { settle(true); return; }
    const run = () => {
      idleId = null;
      if (settled) return;
      if (!alive()) { settle(false); return; }
      // DEFENSE: Other Markdown instances can fill the shared worker queue while this job waits for idle time.
      if (jobs.size >= 64) { settle(true); return; }
      if (!worker) {
        worker = new Worker(new URL('./markdown-worker.mjs', import.meta.url), { type: 'module' });
        worker.onmessage = ({ data }) => {
          const job = jobs.get(data.id);
          // DEFENSE: A worker reply can arrive after the owning parser is disposed or its timeout retires the job.
          if (!job) return;
          try {
            // DEFENSE: Unsupported languages yield no markup; expanded math/highlight output is capped before DOM parsing.
            if (data.markup !== undefined && data.markup.length <= 512 * 1024) job.apply(data.markup);
          }
          finally { job.settle(job.alive()); }
        };
        // DEFENSE: Loading the formatter module or executing user-authored math can fail in the worker; retain source text.
        worker.onerror = resetFormatter;
      }
      jobId = ++serial;
      jobs.set(jobId, { alive, settle, apply: markup => {
        if (!alive() || !node.isConnected) return;
        const selection = node.ownerDocument.getSelection();
        if (selection?.rangeCount && selection.getRangeAt(0).intersectsNode(node)) return;
        // Only trusted formatter output is parsed, never raw model HTML. A
        // second allowlist keeps formatter output a non-interactive fragment.
        const parsed = new DOMParser().parseFromString(markup, 'text/html');
        const children = [...parsed.body.childNodes].map(source => cleanFormatterFragment(source, node.ownerDocument));
        const changed = node.dataset.decorated !== kind || node.childNodes.length !== children.length
          || children.some((child, index) => !child.isEqualNode(node.childNodes[index]));
        if (changed) {
          node.replaceChildren(...children);
          node.dataset.decorated = kind;
          onChange?.();
        }
      } });
      // DEFENSE: User-authored math/highlighting may stall the worker; retire it after the existing five-second budget.
      timer = setTimeout(resetFormatter, 5000);
      worker.postMessage({ id: jobId, kind, text, language });
    };
    idleId = idle(run, { timeout: 500 });
  });
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
    this.parserEnded = false;
    this.decorations = new Set();
    this.decorationController = new AbortController();
    this.settled = new Promise(resolve => { this.resolveSettled = resolve; });
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
    const close = (completed) => {
      const entry = stack.pop();
      delete entry.node.dataset.pending;
      if (stack.length === 1) { entry.node.dataset.stable = 'true'; this.stableBlocks++; }
      const kind = [smd.CODE_BLOCK, smd.CODE_FENCE].includes(entry.type) ? 'code'
        : [smd.EQUATION_BLOCK, smd.EQUATION_INLINE].includes(entry.type) ? 'math' : null;
      if (kind === 'math' && !completed) {
        const source = entry.equation.opener + (entry.equation.openingNewline ? '\n' : '') + entry.node.textContent;
        entry.node.replaceWith(document.createTextNode(source));
        return;
      }
      if (kind) {
        const pending = decorate(entry.node, kind, entry.node.textContent, entry.node.dataset.language,
          () => !this.disposed, this.decorationController.signal, () => options.onChange?.());
        this.decorations.add(pending);
        pending.then(() => { this.decorations.delete(pending); this.settleIfFinished(); });
      }
    };
    const sink = {
      data: null,
      add_token: (_, type, equation) => {
        if (type === smd.DOCUMENT) return;
        let parent = stack.at(-1).node;
        let node;
        if ([smd.CODE_BLOCK, smd.CODE_FENCE].includes(type)) {
          const block = document.createElement('div'); block.className = 'code-block';
          const toolbar = document.createElement('div'); toolbar.className = 'code-toolbar';
          const ui = document.createElement('div'); ui.className = 'interactive-markdown-target';
          const pre = document.createElement('pre'); node = document.createElement('code');
          const identity = ordinal++;
          const key = options.codeKey?.(identity);
          if (key) {
            options.target?.(`${key}/toolbar`, toolbar);
            options.target?.(`${key}/code`, node);
            options.target?.(`${key}/source`, pre);
            options.target?.(`${key}/ui`, ui);
            options.target?.(`${key}/frame`, block);
          }
          codeSources.set(node, { ordinal: identity, text: null });
          pre.append(node); block.append(toolbar, pre, ui); parent.append(block);
        } else {
          node = document.createElement(tags.get(type));
          if (type === smd.TABLE) {
            const scroll = document.createElement('div'); scroll.className = 'table-scroll'; parent.append(scroll); parent = scroll;
          }
          if (type === smd.CHECKBOX) { node.type = 'checkbox'; node.disabled = true; }
          if (type === smd.IMAGE) { node.className = 'markdown-image-link'; node.setAttribute('aria-label', 'Image link (not loaded automatically)'); }
          if ([smd.EQUATION_BLOCK, smd.EQUATION_INLINE].includes(type)) { node.className = 'math-source'; node.dataset.language = type === smd.EQUATION_BLOCK ? 'display' : 'inline'; }
          parent.append(node);
        }
        node.dataset.pending = 'true';
        stack.push({ node, type, equation });
      },
      end_token: (_, completed = true) => close(completed),
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
        // DEFENSE: Markdown list starts are arbitrary source text; only bounded decimal indices may become native start attributes.
        else if (attr === smd.START && /^\d{1,9}$/.test(value)) node.setAttribute('start', value);
      },
    };
    const parser = smd.parser(sink);
    this.buffer = new PacedText(chunk => { smd.parser_write(parser, chunk); reportCode(); options.onChange?.(); }, () => {
      smd.parser_end(parser);
      while (stack.length > 1) close(false);
      reportCode(); options.onChange?.();
      this.parserEnded = true;
      this.settleIfFinished();
    }, options);
  }
  get text() { return this.buffer.target; }
  append(text) { this.buffer.append(text); }
  finish() { this.buffer.finish(); }
  async whenCaughtUp(length = this.buffer.target.length) {
    if (!await this.buffer.whenCaughtUp(length) || this.disposed) return false;
    // A measurement snapshot waits only for work already introduced by its prefix.
    const decorations = [...this.decorations];
    if ((await Promise.all(decorations)).some(done => !done)) return false;
    return !this.disposed;
  }
  // Parser and formatting completion excludes image decoding and document fonts.
  whenSettled() { return this.disposed ? Promise.resolve(false) : this.settled; }
  settleIfFinished() {
    if (!this.disposed && this.parserEnded && this.decorations.size === 0) this.resolveSettled(true);
  }
  dispose() {
    this.disposed = true;
    this.buffer.dispose();
    this.decorationController.abort();
    this.resolveSettled(false);
  }
}
