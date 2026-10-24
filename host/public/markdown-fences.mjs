import { PacedText } from './markdown.mjs';
import { createMarkdownFenceParser } from './markdown-fence-observation.mjs';

/** Observe the pinned Markdown parser; eligibility and DSL meaning belong to the extracted model. */
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
    const reported = new Map();
    const parser = createMarkdownFenceParser((fences, prefix) => {
      if (this.disposed || generation !== this.generation) return;
      for (const fence of fences) {
        const signature = JSON.stringify([fence.info, fence.code, fence.closed, this.ending, this.ending !== 'open' && prefix === this.text]);
        if (signature === reported.get(fence.ordinal)) continue;
        reported.set(fence.ordinal, signature);
        this.options.onFence?.({
          ordinal: fence.ordinal, kind: fence.kind, info: fence.info,
          infoComplete: true, code: fence.code, closed: fence.closed,
          inputPrefix: prefix, inputRevision: this.revision, epoch: this.epoch,
          ending: this.ending,
        });
      }
      this.options.onChange?.();
    });
    this.buffer = new PacedText(chunk => {
      parser.write(chunk);
    }, () => parser.finish(), { ...this.options, smooth: false });
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
