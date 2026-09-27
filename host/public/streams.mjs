import { Markdown } from './markdown.mjs';

// Disposable transport previews, not task state. Only a start observed on this
// connection admits a preview; reconnect never guesses a missing delta prefix.
export class Streams {
  constructor({ createMarkdown = (root, options) => new Markdown(root, options) } = {}) {
    this.createMarkdown = createMarkdown;
    this.sessions = new Map();
    this.root = null;
    this.selected = null;
    this.revision = 0;
    this.characters = 0;
  }
  drop(key) {
    const session = this.sessions.get(key);
    if (!session) return;
    for (const item of session.items.values()) {
      this.characters -= item.text.length;
      if (!item.adopted) item.markdown?.dispose();
      item.container?.remove();
    }
    this.sessions.delete(key);
  }
  clear() { for (const key of this.sessions.keys()) this.drop(key); }
  receive(notice) {
    if (!Number.isSafeInteger(notice.task_id) || notice.task_id < 0 || !Number.isSafeInteger(notice.ticket) || notice.ticket < 0) return;
    const key = `${notice.task_id}:${notice.ticket}`;
    if (notice.type === 'stream_start') {
      if (this.sessions.has(key)) return;
      if (this.sessions.size >= 16) this.drop(this.sessions.keys().next().value);
      this.sessions.set(key, { task: notice.task_id, items: new Map(), ended: null });
      return;
    }
    const session = this.sessions.get(key);
    if (!session) return;
    if (notice.type === 'stream_cancel') { this.drop(key); return; }
    if (notice.type === 'stream_end') {
      if (!Number.isSafeInteger(notice.sequence)) return;
      session.ended = notice.sequence;
      for (const item of session.items.values()) item.markdown?.finish();
      if (session.ended <= this.revision) this.drop(key);
      return;
    }
    if (notice.type !== 'delta' || session.ended !== null || typeof notice.text !== 'string' ||
        !Number.isSafeInteger(notice.output_index) || notice.output_index < 0) return;
    let item = session.items.get(notice.output_index);
    if (!item) {
      if (session.items.size >= 32) { this.drop(key); return; }
      item = { text: '', markdown: null, container: null, adopted: false };
      session.items.set(notice.output_index, item);
    }
    if (this.characters + notice.text.length > 8 * 1024 * 1024 || item.text.length + notice.text.length > 4 * 1024 * 1024) {
      this.drop(key); return;
    }
    item.text += notice.text;
    this.characters += notice.text.length;
    if (item.markdown) item.markdown.append(notice.text);
    this.attach();
  }
  surface(root, selected, revision) {
    this.root = root ?? null;
    this.selected = selected;
    this.revision = revision;
    for (const [key, session] of this.sessions) if (session.ended !== null && session.ended <= revision) this.drop(key);
    this.attach();
  }
  attach() {
    for (const session of this.sessions.values()) {
      for (const item of session.items.values()) {
        if (item.adopted) continue;
        if (session.task !== this.selected || !this.root) { item.container?.remove(); continue; }
        if (!item.container) {
          const document = this.root.ownerDocument;
          const container = document.createElement('article'); container.className = 'live-preview message';
          const title = document.createElement('div'); title.className = 'stream-author'; title.textContent = 'Agent · streaming preview';
          const body = document.createElement('div'); body.className = 'markdown';
          container.append(title, body);
          item.container = container;
          item.markdown = this.createMarkdown(body, { smooth: !globalThis.matchMedia?.('(prefers-reduced-motion: reduce)').matches });
          item.markdown.append(item.text);
          if (session.ended !== null) item.markdown.finish();
        }
        if (item.container.parentNode !== this.root) this.root.append(item.container);
      }
    }
  }
  take(text, selected, revision) {
    // Adoption requires settlement plus a native presentation of the exact
    // text. Live deltas must never append into a previously committed message.
    for (const session of this.sessions.values()) {
      if (session.task !== selected || session.ended === null || session.ended > revision) continue;
      for (const item of session.items.values()) {
        if (!item.adopted && item.markdown && item.text === text) {
          item.adopted = true;
          item.markdown.finish();
          return item.markdown;
        }
      }
    }
    return null;
  }
}
