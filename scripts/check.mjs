import { readdir } from 'node:fs/promises';
import path from 'node:path';
import { build, root, run } from './build.mjs';
import { auditAssumptions } from './assumptions.mjs';

async function sources(directory) {
  return (await Promise.all((await readdir(path.join(root, directory), { withFileTypes: true })).map(entry => {
    const filename = `${directory}/${entry.name}`;
    if (['node_modules', 'generated', 'vendor'].includes(entry.name)) return [];
    return entry.isDirectory() ? sources(filename) : filename.endsWith('.mjs') ? [filename] : [];
  }))).flat();
}
await build({ check: true });
await auditAssumptions();
await run('bun', ['scripts/check-web-vendor.mjs']);
const scripts = (await Promise.all(['host', 'scripts', 'remote', 'relay', 'plugins', 'tests'].map(sources))).flat();
let cursor = 0;
await Promise.all(Array.from({ length: 4 }, async () => {
  while (cursor < scripts.length) await run('node', ['--check', scripts[cursor++]]);
}));
console.log(`JavaScript: ${scripts.length} syntax checks`);
