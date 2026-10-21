import { readdir, realpath, stat } from 'node:fs/promises';
import path from 'node:path';

const maximumPathBytes = 4096;
const maximumEntries = 512;

/** Observe folder names only; selecting workspace roots remains a native command. */
export async function browseDirectories(location, maximumBytes, { filesystem = { readdir, realpath, stat } } = {}) {
  const { readdir, realpath, stat } = filesystem;
  try {
    // DEFENSE: The browser supplies this path; reject malformed or oversized navigation requests.
    if (typeof location !== 'string' || !path.isAbsolute(location) || location.includes('\0') ||
        Buffer.byteLength(location) > maximumPathBytes) {
      throw new TypeError('Expected a bounded absolute directory path');
    }
    const current = await realpath(location);
    // DEFENSE: Resolving a user-selected link can produce a canonical path beyond the wire path limit.
    if (Buffer.byteLength(current) > maximumPathBytes) throw new TypeError('Directory path exceeds the model boundary');
    // DEFENSE: A browser path can name a file or be replaced by one before observation.
    if (!(await stat(current)).isDirectory()) throw new TypeError('The selected path is not a directory');
    const children = await readdir(current, { withFileTypes: true });
    const entries = [];
    for (const child of children) {
      const childPath = path.join(current, child.name);
      let directory = child.isDirectory();
      if (child.isSymbolicLink()) {
        try { directory = (await stat(childPath)).isDirectory(); }
        catch (error) {
          // DEFENSE: Directory listings can contain broken or cyclic links, which cannot be navigation destinations.
          if (!['ENOENT', 'ENOTDIR', 'ELOOP'].includes(error.code)) throw error;
        }
      }
      if (directory) entries.push({ name: child.name, path: childPath });
    }
    entries.sort((left, right) => left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
    const parent = path.dirname(current);
    const result = { ok: true, path: current, parent: parent === current ? null : parent,
      entries: entries.slice(0, maximumEntries), truncated: entries.length > maximumEntries };
    // DEFENSE: A directory with long child names can exceed the browser frame budget after entry-count limiting.
    if (Buffer.byteLength(JSON.stringify(result)) > maximumBytes) {
      throw new Error('Directory observation exceeds the frame byte limit');
    }
    return result;
  } catch (error) {
    // DEFENSE: Browser-selected paths may disappear or deny access; return the observation's explicit failure envelope.
    return { ok: false, error: error.message };
  }
}
