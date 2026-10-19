import { execFileSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const operation = process.argv[2];
// DEFENSE: A command-line caller can pass unsupported arguments; reject the invocation before running the build operation.
if (!['check', 'update'].includes(operation)) throw new Error('Usage: bun scripts/agents-index.mjs check|update');
const paths = execFileSync('git', ['ls-files', '--cached', '-z'], { cwd: root, encoding: 'utf8' }).split('\0').filter(Boolean);
const directories = new Map();
for (const filename of paths) {
  const parts = filename.split('/');
  for (let i = 0; i < parts.length; i++) {
    const parent = parts.slice(0, i).join('/') || '.';
    const entry = parts[i] + (i + 1 < parts.length ? '/' : '');
    if (!directories.has(parent)) directories.set(parent, new Set());
    directories.get(parent).add(entry);
  }
}
const index = ['[Project Index]|root:.', '|source:git-tracked-files-only', '|excluded:{git-ignored,git-untracked}',
  ...[...directories].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
    .map(([name, entries]) => `|${name}:{${[...entries].sort().join(',')}}`)].join('\n');
const filename = new URL('../AGENTS.md', import.meta.url);
const text = await readFile(filename, 'utf8');
const begin = '<!-- BEGIN AGENTS_MD_PROJECT_INDEX -->';
const end = '<!-- END AGENTS_MD_PROJECT_INDEX -->';
const start = text.indexOf(begin);
const finish = text.indexOf(end, start);
// DEFENSE: An edited AGENTS.md can remove one of the markers needed to replace only the generated index.
if (start < 0 || finish < 0) throw new Error('AGENTS.md has no complete project index markers');
const updated = text.slice(0, start) + `${begin}\n\`\`\`text\n${index}\n\`\`\`\n${end}` + text.slice(finish + end.length);
if (operation === 'update') await writeFile(filename, updated);
// DEFENSE: Changed staged source paths can leave the tracked project index out of date.
else if (text !== updated) throw new Error('AGENTS.md index is stale. Stage changed paths, run bun run index, and stage AGENTS.md.');
console.log(`Project index ${operation === 'update' ? 'updated' : 'checked'} (${paths.length} tracked files).`);
