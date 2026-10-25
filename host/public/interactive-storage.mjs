import { JsonNumber, parseJson, stringifyJson } from './json-tokens.mjs';
/** Physical storage only: definition, schema and value acceptance remain in the extracted model. */
export class InteractiveSnapshotStorage {
  constructor({ storage = null, maximumDocuments, maximumBytes, prefix }) {
    this.storage = storage;
    this.maximumDocuments = maximumDocuments;
    this.maximumBytes = maximumBytes;
    this.prefix = prefix;
    this.pending = new Map();
    this.timer = null;
  }
  get store() { return this.storage ?? globalThis.localStorage; }
  key(storageKey) { return this.prefix + storageKey; }
  load(storageKey) {
    const raw = this.store.getItem(this.key(storageKey));
    if (raw === null) return { present: false };
    return { present: true, value: raw };
  }
  save(storageKey, payload, settled) {
    this.pending.set(this.key(storageKey), { payload, settled });
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
      let savedAt = null;
      // DEFENSE: A different stored entry can contain invalid JSON, JSON null or
      // missing metadata. Such entries count toward capacity and are evicted
      // before dated entries, without blocking another document's save.
      try {
        const valueTime = parseJson(value)?.savedAt;
        const observed = valueTime instanceof JsonNumber ? Number(valueTime.source) : valueTime;
        if (typeof observed === 'number' && Number.isFinite(observed)) savedAt = observed;
      } catch (error) {
        if (error.name !== 'SyntaxError') throw error;
      }
      retained.push({ key, bytes: (key.length + value.length) * 2, savedAt });
    }
    retained.sort((a, b) => (a.savedAt === null ? b.savedAt === null ? 0 : -1 : b.savedAt === null ? 1 : a.savedAt - b.savedAt)
      || a.key.localeCompare(b.key));
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
        const raw = stringifyJson({ payload: entry.payload, savedAt: Date.now() });
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
  remove(storageKey) { this.pending.delete(this.key(storageKey)); this.store.removeItem(this.key(storageKey)); }
  dispose() { this.flush(); }
}
