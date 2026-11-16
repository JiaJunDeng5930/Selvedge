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
  trim(protectedKey, reservedBytes) {
    const storage = this.store;
    const retained = [];
    let bytes = reservedBytes;
    for (const key of Object.keys(storage)) {
      if (!key.startsWith(this.prefix) || key === protectedKey) continue;
      const value = storage.getItem(key);
      // DEFENSE: Another tab can remove a shared localStorage key between enumeration and this read.
      if (value === null) continue;
      const size = (key.length + value.length) * 2;
      bytes += size;
      retained.push({ key, size, value });
    }
    const overCapacity = () => retained.length + 1 > this.maximumDocuments || bytes > this.maximumBytes;
    if (!overCapacity()) return false;
    for (const entry of retained) {
      let savedAt = null;
      // DEFENSE: A different stored entry can contain invalid JSON, JSON null or
      // missing metadata. Such entries count toward capacity and are evicted
      // before dated entries, without blocking another document's save.
      try {
        const valueTime = parseJson(entry.value)?.savedAt;
        const observed = valueTime instanceof JsonNumber ? Number(valueTime.source) : valueTime;
        if (typeof observed === 'number' && Number.isFinite(observed)) savedAt = observed;
      } catch (error) {
        if (error.name !== 'SyntaxError') throw error;
      }
      entry.savedAt = savedAt;
    }
    retained.sort((a, b) => (a.savedAt === null ? b.savedAt === null ? 0 : -1 : b.savedAt === null ? 1 : a.savedAt - b.savedAt)
      || a.key.localeCompare(b.key));
    while (overCapacity()) {
      const evicted = retained.shift();
      storage.removeItem(evicted.key);
      bytes -= evicted.size;
    }
    return true;
  }
  flush() {
    if (this.timer !== null) clearTimeout(this.timer);
    this.timer = null;
    for (const [key, entry] of this.pending) {
      this.pending.delete(key);
      let failure = null;
      try {
        const raw = stringifyJson({ payload: entry.payload, savedAt: Date.now() });
        const bytes = (key.length + raw.length) * 2;
        // DEFENSE: User-authored interactive values can exceed the configured physical storage budget.
        if (bytes > this.maximumBytes) throw new RangeError('Interactive snapshot exceeds storage capacity');
        try { this.store.setItem(key, raw); }
        // DEFENSE: A browser quota can block a write whose eviction would otherwise free enough storage.
        catch (error) {
          if (error.name !== 'QuotaExceededError' || !this.trim(key, bytes)) throw error;
          this.store.setItem(key, raw);
        }
        this.trim(key, bytes);
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
