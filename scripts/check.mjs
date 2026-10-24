import { readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { parse } from 'acorn';
import { build, root, run } from './build.mjs';

async function sources(directory) {
  return (await Promise.all((await readdir(path.join(root, directory), { withFileTypes: true })).map(entry => {
    const filename = `${directory}/${entry.name}`;
    if (['node_modules', 'generated', 'vendor'].includes(entry.name)) return [];
    return entry.isDirectory() ? sources(filename) : filename.endsWith('.mjs') ? [filename] : [];
  }))).flat();
}

export async function check(buildResult) {
  const completed = buildResult ?? await build({ check: true });
  if (!completed.checked) throw new Error('Repository check requires a complete checked production build');
  await run('bash', ['-n', 'scripts/bootstrap.sh']);
  await run('bun', ['scripts/check-web-vendor.mjs']);
  const scripts = (await Promise.all(['host', 'scripts', 'remote', 'relay', 'plugins', 'examples', 'tests'].map(sources))).flat();
  let cursor = 0;
  await Promise.all(Array.from({ length: 4 }, async () => {
    while (cursor < scripts.length) {
      const filename = scripts[cursor++];
      const source = await Bun.file(path.join(root, filename)).text();
      try {
        parse(source, { ecmaVersion: 'latest', sourceType: 'module' });
      } catch (error) {
        throw new Error(`JavaScript syntax check failed: ${filename}`, { cause: error });
      }
    }
  }));
  console.log(`JavaScript: ${scripts.length} syntax checks`);
  return completed;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await check();
