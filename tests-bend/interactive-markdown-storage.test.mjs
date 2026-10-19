import { test, expect } from 'bun:test';
import { InteractiveSnapshotStorage } from '../host/public/interactive-storage.mjs';

class Storage {
  #values = new Map();
  get length() { return this.#values.size; }
  key(index) { return [...this.#values.keys()][index] ?? null; }
  getItem(key) { return this.#values.get(key) ?? null; }
  setItem(key, value) {
    this.#values.set(key, value);
    Object.defineProperty(this, key, { value, writable: true, configurable: true, enumerable: true });
  }
  removeItem(key) { this.#values.delete(key); delete this[key]; }
}
const owner = key => ({ key, epoch: 1n });

test('buffered snapshots keep the latest value, isolate owners and cancel removed writes', () => {
  const storage = new Storage();
  const io = new InteractiveSnapshotStorage({ storage });
  const original = owner('store/a/viewer/1/output/1/2/part/0/code/0');
  const branch = owner('store/a/viewer/2/output/1/2/part/0/code/0');
  io.save(original, '<ui id="one" />', { value: 1 });
  io.save(original, '<ui id="one" />', { value: 2 });
  io.save(branch, '<ui id="one" />', { value: 9 });
  io.save(owner('removed'), 'definition', {});
  io.remove(owner('removed'));
  io.dispose();
  expect(io.load(original).payload).toEqual({ value: 2 });
  expect(io.load(branch).payload).toEqual({ value: 9 });
  expect(io.load(owner('store/b/viewer/1/output/1/2/part/0/code/0'))).toBeNull();
  expect(io.load(owner('removed'))).toBeNull();
});

test('bounded retention evicts stored documents and preserves unrelated storage', () => {
  const storage = new Storage();
  storage.setItem('unrelated-preference', 'kept');
  const io = new InteractiveSnapshotStorage({ storage, maximumDocuments: 2, maximumBytes: 4096 });
  for (const key of ['a', 'b', 'c']) { io.save(owner(key), 'definition', { key }); io.flush(); }
  expect(storage.length).toBe(3);
  expect(storage.getItem('unrelated-preference')).toBe('kept');
  expect(io.load(owner('c')).payload).toEqual({ key: 'c' });
  io.dispose();
});

test('corrupt physical JSON is rejected without deletion and unavailable writes report failure', () => {
  const storage = new Storage();
  const io = new InteractiveSnapshotStorage({ storage });
  storage.setItem(io.key(owner('bad')), '{');
  expect(() => io.load(owner('bad'))).toThrow(SyntaxError);
  expect(storage.getItem(io.key(owner('bad')))).toBe('{');
  storage.removeItem(io.key(owner('bad')));
  storage.setItem = () => { throw new DOMException('Denied', 'SecurityError'); };
  let result;
  io.save(owner('blocked'), 'definition', {}, (success, message) => { result = { success, message }; });
  io.flush();
  expect(result.success).toBe(false);
  expect(result.message).toContain('Denied');
  io.dispose();
});
