/** Physical storage only: definition, schema and value acceptance remain in Bend. */
export class InteractiveSnapshotStorage {
  constructor({ storage = null, maximumDocuments = 100, maximumBytes = 5 * 1024 * 1024 } = {}) {
    this.storage = storage;
    this.maximumDocuments = maximumDocuments;
    this.maximumBytes = maximumBytes;
    this.prefix = 'selvedge-interactive-v1/';
    this.pending = new Map();
    this.timer = null;
  }
  get store() { return this.storage ?? globalThis.localStorage; }
  key(owner) { return this.prefix + owner.key; }
  load(owner) {
    const raw = this.store.getItem(this.key(owner));
    if (raw === null) return null;
    return JSON.parse(raw);
  }
  save(owner, definition, payload, settled) {
    this.pending.set(this.key(owner), { definition, payload, settled });
    if (this.timer === null) this.timer = setTimeout(() => this.flush(), 150);
  }
  trim(protectedKey = null, reservedBytes = 0) {
    const storage = this.store;
    const retained = [];
    for (const key of Object.keys(storage)) {
      if (!key.startsWith(this.prefix) || key === protectedKey) continue;
      const value = storage.getItem(key);
      // DEFENSE: Another tab can remove a shared localStorage key between enumeration and this read.
      if (value === null) continue;
      const { savedAt } = JSON.parse(value);
      retained.push({ key, bytes: (key.length + value.length) * 2, savedAt });
    }
    retained.sort((a, b) => a.savedAt - b.savedAt || a.key.localeCompare(b.key));
    let bytes = retained.reduce((sum, item) => sum + item.bytes, reservedBytes);
    const reservedDocuments = protectedKey === null ? 0 : 1;
    while (retained.length + reservedDocuments > this.maximumDocuments || bytes > this.maximumBytes) {
      const evicted = retained.shift();
      // DEFENSE: A single protected snapshot can exceed the byte budget after every other snapshot is evicted.
      if (!evicted) throw new RangeError('Interactive snapshot exceeds storage capacity');
      storage.removeItem(evicted.key);
      bytes -= evicted.bytes;
    }
  }
  flush() {
    if (this.timer !== null) clearTimeout(this.timer);
    this.timer = null;
    for (const [key, entry] of this.pending) {
      this.pending.delete(key);
      let failure = null;
      try {
        const raw = JSON.stringify({ definition: entry.definition, payload: entry.payload, savedAt: Date.now() });
        // DEFENSE: User-authored interactive values can exceed the configured physical storage budget.
        if (raw.length * 2 > this.maximumBytes) throw new RangeError('Interactive snapshot exceeds storage capacity');
        this.trim(key, (key.length + raw.length) * 2);
        this.store.setItem(key, raw);
        this.trim();
      } catch (error) {
        // DEFENSE: Storage may deny access, exhaust quota, or contain invalid JSON; report these failures to the owning document.
        if (!['SecurityError', 'QuotaExceededError', 'SyntaxError', 'RangeError'].includes(error.name)) throw error;
        failure = error;
      }
      entry.settled?.(failure === null, failure === null ? '' : String(failure));
    }
  }
  remove(owner) { this.pending.delete(this.key(owner)); this.store.removeItem(this.key(owner)); }
  dispose() { this.flush(); }
}
