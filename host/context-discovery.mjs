import { lstat, opendir, realpath } from 'node:fs/promises';
import path from 'node:path';
import { boundary } from './public/model-boundary.mjs';

const descriptors = new WeakMap();
export function contextDescriptor(observer) {
  if (!descriptors.has(observer)) descriptors.set(observer, boundary('control.context.descriptor', { observer }));
  return descriptors.get(observer);
}
export const isContextDiscovery = observer => contextDescriptor(observer).discovery;

/** Execute filesystem primitives emitted by the extracted discovery controller. */
export function createContextDiscovery({ home, settings, signal, filesystem = { lstat, opendir, realpath }, candidates = [], maximum }) {
  const prefetched = new Map();
  const kind = stat => stat === null ? 'missing' : stat.isSymbolicLink() ? 'link'
    : stat.isFile() ? 'file' : stat.isDirectory() ? 'directory' : 'other';

  async function probe(filename) {
    try { return kind(await filesystem.lstat(filename)); }
    // DEFENSE: Optional guidance/skill files can disappear while their directory is observed.
    catch (error) { if (error.code === 'ENOENT') return 'missing'; throw error; }
  }

  async function inspect(effect) {
    signal?.throwIfAborted();
    const folder = effect.folder;
    if (filesystem.prefetchDirectory) {
      if (!prefetched.has(folder)) prefetched.set(folder, filesystem.prefetchDirectory(folder, { candidates, maximum }));
      await prefetched.get(folder);
    }
    const stat = await filesystem.lstat(folder);
    const canonical = stat.isDirectory() && !stat.isSymbolicLink() && await filesystem.realpath(folder) === folder;
    const observation = { canonical, parent: path.dirname(folder), probes: [], entries: [] };
    if (!canonical) return observation;
    observation.probes = await Promise.all(effect.probes.map(async name => ({ name, kind: await probe(path.join(folder, name)) })));
    if (effect.entries) {
      const stream = await filesystem.opendir(folder);
      for await (const entry of stream) {
        signal?.throwIfAborted();
        observation.entries.push({ name: entry.name, path: path.join(folder, entry.name), kind: kind(entry) });
        // The controller requests one extra observation to distinguish an exhausted budget from a complete stream.
        if (observation.entries.length > effect.maximum) break;
      }
    }
    return observation;
  }

  return async function discover(observer) {
    let result = boundary('control.context.start', { observer, home, workspace: settings.workspace });
    while (!result.done) {
      let observation;
      try { observation = await inspect(result.effects[0]); }
      catch (error) { signal?.throwIfAborted(); observation = { error: error.message }; }
      result = boundary('control.context.step', { state: result.state, observation });
    }
    if (result.error !== null) throw new Error(result.error);
    return result.entries;
  };
}
