import { lstat, opendir, realpath } from 'node:fs/promises';
import path from 'node:path';
import { boundary } from './public/model-boundary.mjs';

const descriptors = new WeakMap();
export function contextDescriptor(observer) {
  if (!descriptors.has(observer)) descriptors.set(observer, boundary('control.context.descriptor', { observer }));
  return descriptors.get(observer);
}
export const isContextDiscovery = observer => contextDescriptor(observer).discovery;

/** Run the same admitted workspace discovery on the machine that owns the files. */
export async function discoverExecutionContext({ workspace, observers }, home) {
  const definitions = boundary('config.context_definitions', {});
  const discover = createContextDiscovery({ home, settings: { workspace } });
  return Promise.all(observers.map(async type => {
    const { observer } = definitions.find(definition => definition.observer.type === type);
    try { return { type, entries: await discover(observer), error: null }; }
    // DEFENSE: An unreadable directory makes its collection incomplete without
    // withdrawing sources accepted by other, independently observed collections.
    catch (error) { return { type, entries: [], error: error.message }; }
  }));
}

/** Execute filesystem primitives emitted by the extracted discovery controller. */
export function createContextDiscovery({ home, settings, signal, filesystem = { lstat, opendir, realpath }, candidates = [], maximum }) {
  const prefetched = new Map();
  const metadata = new Map();
  const canonicalPaths = new Map();
  const listings = new Map();
  const kind = stat => stat === null ? 'missing' : stat.isSymbolicLink() ? 'link'
    : stat.isFile() ? 'file' : stat.isDirectory() ? 'directory' : 'other';

  function observeOnce(observations, filename, read) {
    if (!observations.has(filename)) observations.set(filename, read(filename));
    return observations.get(filename);
  }

  const observeMetadata = filename => observeOnce(metadata, filename, file => filesystem.lstat(file));

  async function probe(filename) {
    try { return kind(await observeMetadata(filename)); }
    // DEFENSE: Optional guidance/skill files can disappear while their directory is observed.
    catch (error) { if (error.code === 'ENOENT') return 'missing'; throw error; }
  }

  async function listDirectory(folder, limit) {
    const previous = listings.get(folder);
    if (previous) {
      const listing = await previous;
      if (listing.complete || listing.entries.length > limit) return listing.entries.slice(0, limit + 1);
    }
    const read = async () => {
      const entries = [];
      for await (const entry of await filesystem.opendir(folder)) {
        signal?.throwIfAborted();
        entries.push({ name: entry.name, path: path.join(folder, entry.name), kind: kind(entry) });
        // One extra entry distinguishes an exhausted budget from a complete directory.
        if (entries.length > limit) return { entries, complete: false };
      }
      return { entries, complete: true };
    };
    const current = read();
    listings.set(folder, current);
    return (await current).entries;
  }

  async function inspect(effect) {
    signal?.throwIfAborted();
    const folder = effect.folder;
    if (filesystem.prefetchDirectory) {
      if (!prefetched.has(folder)) prefetched.set(folder, filesystem.prefetchDirectory(folder, { candidates, maximum }));
      await prefetched.get(folder);
    }
    const stat = await observeMetadata(folder);
    const canonical = stat.isDirectory() &&
      await observeOnce(canonicalPaths, folder, file => filesystem.realpath(file)) === folder;
    const observation = { canonical, parent: path.dirname(folder), probes: [], entries: [] };
    if (!canonical) return observation;
    observation.probes = await Promise.all(effect.probes.map(async name => ({ name, kind: await probe(path.join(folder, name)) })));
    if (effect.entries) observation.entries = await listDirectory(folder, effect.maximum);
    return observation;
  }

  return async function discover(observer) {
    let result = boundary('control.context.start', { observer, home, workspace: settings.workspace });
    while (result.effect !== null) {
      let observation;
      try { observation = await inspect(result.effect); }
      catch (error) { signal?.throwIfAborted(); observation = { error: error.message }; }
      result = boundary('control.context.step', { state: result.state, observation });
    }
    if (result.state.error !== null) throw new Error(result.state.error);
    return result.state.sources;
  };
}
