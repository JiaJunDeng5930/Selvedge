import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';

const readme = new URL('../theory/README.md', import.meta.url);
const begin = '<!-- BEGIN CHECKED_THEORY_INVENTORY -->';
const end = '<!-- END CHECKED_THEORY_INVENTORY -->';

export async function inventory() {
  const algebra = JSON.parse(await readFile(new URL('../theory/stdlib-certificates.json', import.meta.url), 'utf8'));
  const relations = JSON.parse(await readFile(new URL('../theory/relation-certificates.json', import.meta.url), 'utf8'));
  const maps = JSON.parse(await readFile(new URL('../theory/rocq-maps.json', import.meta.url), 'utf8'));
  const applications = relations.entities.filter(([name]) => name.startsWith('ExportRelations.'));
  const records = [
    `${algebra.entities.length + relations.entities.length + maps.entities.length} quoted entities: ${algebra.entities.length} algebra/iteration, ` +
      `${relations.entities.length} relation, and ${maps.entities.length} association-map entities. Relations include ` +
      `${relations.entities.length - applications.length} upstream definitions/theorems and ${applications.length} explicit applications. ` +
      'The map bundle contains four upstream definitions/proofs plus one theorem application and its three reflection-premise definitions.',
    '', '| Quoted entity | Checked Bend use |', '| --- | --- |',
  ];
  for (const [name] of algebra.entities) records.push(`| \`${name}\` | \`stdlib.${name.split('.').at(-1)}\` |`);
  for (const [name] of relations.entities) {
    const target = name.endsWith('.relation') || name.endsWith('.inclusion') || name.endsWith('.clos_refl_trans_ind') || name.endsWith('.clos_refl_trans_ind_left')
      ? 'Original dependency body specialized at its application'
      : `\`relations.${name.split('.').at(-1)}\``;
    records.push(`| \`${name}\` | ${target} |`);
  }
  for (const [name] of maps.entities) {
    const target = name.endsWith('.alist_find') ? '`association-map.find`' : name.endsWith('.alist_remove') || name.endsWith('.filter')
      ? '`association-map.remove` (source filter specialization)' : name.endsWith('.remove_eq_alist')
        ? '`association-map.removal_absence` (original induction body)' : 'Checked Boolean-relation instance in `scripts/ExportMaps.v`';
    records.push(`| \`${name}\` | ${target} |`);
  }
  return records.join('\n');
}

export async function checkTheoryIndex({ update = false } = {}) {
  const source = await readFile(readme, 'utf8');
  const first = source.indexOf(begin);
  const last = source.indexOf(end);
  if (first < 0 || last < first || source.indexOf(begin, first + begin.length) !== -1 || source.indexOf(end, last + end.length) !== -1) {
    throw new Error('Theory inventory must have exactly one ordered marker pair');
  }
  const expected = source.slice(0, first + begin.length) + '\n\n' + await inventory() + '\n\n' + source.slice(last);
  if (update) await writeFile(readme, expected);
  else if (source !== expected) throw new Error('Theory inventory is stale; run bun scripts/theory-index.mjs update');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!['check', 'update'].includes(process.argv[2] ?? 'check')) throw new Error('Usage: theory-index.mjs [check|update]');
  await checkTheoryIndex({ update: process.argv[2] === 'update' });
  console.log(`Theory inventory matches the quoted certificates (${fileURLToPath(readme)}).`);
}
