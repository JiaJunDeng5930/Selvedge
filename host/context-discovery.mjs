import { lstat, opendir, realpath } from 'node:fs/promises';
import path from 'node:path';

const discoveryTypes = new Set(['home_guidance', 'primary_guidance', 'workspace_guidance', 'home_skills', 'workspace_skills']);

export function isContextDiscovery(observer) {
  return discoveryTypes.has(observer.type);
}

/** Interpret the kernel's bounded directory-discovery plan for one observation. */
export function createContextDiscovery({ home, settings, signal }) {
  const roots = settings.workspace.roots;
  const primary = settings.workspace.primary_root;
  const trees = new Map();

  async function directory(filename) {
    signal?.throwIfAborted();
    const stat = await lstat(filename);
    if (!stat.isDirectory() || stat.isSymbolicLink() || await realpath(filename) !== filename) {
      throw new Error(`Context discovery requires a canonical directory without symbolic links: ${filename}`);
    }
    return stat;
  }

  async function exists(filename) {
    signal?.throwIfAborted();
    try { return await lstat(filename); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
  }

  async function selectedFile(folder, files) {
    await directory(folder);
    for (const name of files) {
      const filename = path.join(folder, name);
      const stat = await exists(filename);
      if (stat === null) continue;
      if (!stat.isFile() || stat.isSymbolicLink()) {
        throw new Error(`Context discovery source must be a regular file without symbolic links: ${filename}`);
      }
      return filename;
    }
    return undefined;
  }

  async function ancestors(root, policy, budget) {
    const chain = [];
    let current = root;
    for (;;) {
      await directory(current);
      budget.directory(current);
      chain.push(current);
      for (const marker of policy.repository_markers) {
        if (await exists(path.join(current, marker))) return chain.reverse();
      }
      const parent = path.dirname(current);
      if (parent === current) return [root];
      current = parent;
    }
  }

  function counter(policy, initial = { directories: [], entries: 0 }) {
    const directories = new Set(initial.directories);
    let entries = initial.entries;
    return {
      directory(filename) {
        directories.add(filename);
        if (directories.size > policy.max_directories) throw new Error('Context discovery directory budget exceeded');
      },
      entry() {
        if (++entries > policy.max_entries) throw new Error('Context discovery entry budget exceeded');
      },
      snapshot() { return { directories: [...directories], entries }; },
    };
  }

  async function tree(root, policy, budget, stopAtSkill = false) {
    const folders = [];
    const pending = [root];
    const excluded = new Set(policy.excluded);
    while (pending.length) {
      signal?.throwIfAborted();
      const folder = pending.pop();
      await directory(folder);
      budget.directory(folder);
      folders.push(folder);
      if (stopAtSkill && await selectedFile(folder, policy.files)) continue;
      const children = [];
      const stream = await opendir(folder);
      for await (const entry of stream) {
        signal?.throwIfAborted();
        budget.entry();
        if (!entry.isDirectory() || entry.isSymbolicLink() || excluded.has(entry.name)) continue;
        children.push(path.join(folder, entry.name));
      }
      // Reverse insertion gives deterministic parent-before-child lexical order.
      children.sort().reverse();
      pending.push(...children);
    }
    return folders;
  }

  async function workspaceDirectories(policy) {
    const key = JSON.stringify([policy.repository_markers, policy.excluded, policy.max_directories, policy.max_entries]);
    if (!trees.has(key)) trees.set(key, (async () => {
      const budget = counter(policy);
      const result = [];
      for (const root of roots) {
        const parents = await ancestors(root, policy, budget);
        const descendants = await tree(root, policy, budget);
        result.push({ root, folders: [...parents.slice(0, -1), ...descendants] });
      }
      return { owners: result, budget: budget.snapshot() };
    })());
    return trees.get(key);
  }

  function entry(filename, workspace, folder, global = false) {
    return { filename, workspace,
      observations: { path: filename, applies_to: global ? '*' : folder, precedence: folder } };
  }

  return async function discover(observer) {
    const policy = observer.policy;
    const result = [];
    function add(item) {
      result.push(item);
      if (result.length > policy.max_sources) throw new Error('Context discovery source budget exceeded');
    }
    switch (observer.type) {
      case 'home_guidance': {
        const filename = await selectedFile(home, policy.files);
        if (filename) add(entry(filename, primary, home, true));
        break;
      }
      case 'primary_guidance': {
        if (primary === null) break;
        const filename = await selectedFile(primary, policy.files);
        if (filename) add(entry(filename, primary, primary));
        break;
      }
      case 'workspace_guidance': {
        for (const { root, folders } of (await workspaceDirectories(policy)).owners) {
          for (const folder of folders) {
            if (root === primary && folder === primary) continue;
            const filename = await selectedFile(folder, policy.files);
            if (filename) add(entry(filename, root, folder));
          }
        }
        break;
      }
      case 'home_skills':
      case 'workspace_skills': {
        const global = observer.type === 'home_skills';
        const scanned = global ? { owners: [{ root: primary, folders: [home] }] } : await workspaceDirectories(policy);
        const { owners } = scanned;
        const budget = counter(policy, scanned.budget);
        const seen = new Set();
        for (const { root, folders } of owners) {
          for (const folder of folders) {
            for (const relative of policy.directories) {
              const container = path.join(folder, relative);
              if (await exists(container) === null) continue;
              for (const candidate of await tree(container, policy, budget, true)) {
                const filename = await selectedFile(candidate, policy.files);
                if (filename === undefined) continue;
                const identity = JSON.stringify([root, filename]);
                if (seen.has(identity)) continue;
                seen.add(identity);
                add(entry(filename, root, folder, global));
              }
            }
          }
        }
        break;
      }
      default: throw new TypeError('Unknown context discovery strategy');
    }
    return result;
  };
}
