import * as smd from './vendor/streaming-markdown.mjs';
import { PacedText } from './markdown.mjs';

/** Observe the pinned Markdown parser; eligibility and DSL meaning belong to Bend. */
export class MarkdownFenceObserver {
  constructor(options = {}) {
    this.options = options;
    this.disposed = false;
    this.epoch = null;
    this.revision = 0n;
    this.text = '';
    this.ending = 'open';
    this.generation = 0;
    this.buffer = null;
  }
  reset(epoch) {
    this.buffer?.dispose();
    this.epoch = epoch;
    this.text = '';
    this.ending = 'open';
    const generation = ++this.generation;
    const stack = [];
    const fences = [];
    let ordinal = 0n;
    let prefix = '';
    const report = () => {
      if (this.disposed || generation !== this.generation) return;
      for (const fence of fences) {
        const signature = JSON.stringify([fence.info, fence.code, fence.closed, this.ending, this.ending !== 'open' && prefix === this.text]);
        if (signature === fence.reported) continue;
        fence.reported = signature;
        this.options.onFence?.({
          ordinal: fence.ordinal, kind: fence.kind, info: fence.info,
          infoComplete: true, code: fence.code, closed: fence.closed,
          inputPrefix: prefix, inputRevision: this.revision, epoch: this.epoch,
          ending: this.ending,
        });
      }
      this.options.onChange?.();
    };
    const sink = {
      data: null,
      add_token: (_, type) => {
        if (type === smd.DOCUMENT) return;
        let fence = null;
        if (type === smd.CODE_BLOCK || type === smd.CODE_FENCE) {
          fence = { ordinal: ordinal++, kind: type === smd.CODE_FENCE ? 'fenced' : 'indented',
            info: '', code: '', closed: false, reported: null };
          fences.push(fence);
        }
        stack.push({ type, fence });
      },
      end_token: () => {
        const entry = stack.pop();
        if (entry.fence) entry.fence.closed = true;
      },
      add_text: (_, value) => {
        const fence = stack.at(-1)?.fence;
        if (fence) fence.code += value;
      },
      set_attr: (_, attr, value) => {
        if (attr === smd.LANG && stack.at(-1)?.fence) stack.at(-1).fence.info = value;
      },
    };
    const parser = smd.parser(sink);
    this.buffer = new PacedText(chunk => {
      prefix += chunk;
      smd.parser_write(parser, chunk);
      report();
    }, () => {
      smd.parser_end(parser);
      report();
    }, { ...this.options, smooth: false });
  }
  sync({ text, epoch, revision, ending }) {
    if (this.disposed) return;
    if (!this.buffer || epoch !== this.epoch || !text.startsWith(this.text)
        || this.ending !== 'open' && text !== this.text) this.reset(epoch);
    const suffix = text.slice(this.text.length);
    const terminal = this.ending === 'open' && ending !== 'open';
    this.text = text;
    this.revision = revision;
    this.ending = ending;
    if (suffix) this.buffer.append(suffix);
    if (terminal) this.buffer.finish();
  }
  async whenCaughtUp(length = this.text.length) {
    if (this.disposed || !this.buffer) return false;
    const buffer = this.buffer;
    if (!await buffer.whenCaughtUp(length)) return false;
    // End-of-input may flush a final fence delimiter held by the Markdown parser.
    if (this.ending !== 'open' && !await buffer.whenFinished()) return false;
    return !this.disposed && buffer === this.buffer;
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.generation++;
    this.buffer?.dispose();
    this.buffer = null;
  }
}
