import { copyFile, mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { build } from './build.mjs';
import { root, run } from './build-tools.mjs';
import { dependencyFlags, moduleName, sourceFiles } from './rocq-sources.mjs';
import { scanJavaScript } from './audit-paths/javascript.mjs';

const validatedRules = new Map([
  ['filter → length', 'Count matching elements directly. Selvedge.Foundation.ListCountProofs.count_selected.'],
  ['map → length', 'Mapping preserves the length of the input list. Stdlib.Lists.List.length_map.'],
  ['filter → hd_error', 'Find the first element satisfying the filter.'],
  ['filter → find', 'Find using the conjunction of both predicates.'],
]);

async function scanRocq(directory, filenames) {
  const flags = [...dependencyFlags, '-Q', path.relative(root, directory), 'SelvedgePathAudit'];
  await copyFile(path.join(root, 'scripts/audit-paths/Scan.v'), path.join(directory, 'Scan.v'));
  await run('rocq', ['compile', ...flags, path.join(directory, 'Scan.v')]);
  const unavailable = [];
  const findings = [];
  let scanned = 0;
  let batchNumber = 0;

  async function scanBatch(batch) {
    const job = path.join(directory, `Batch${batchNumber++}.v`);
    const names = batch.map(moduleName);
    const source = [
      'From Stdlib Require Import String List.',
      'From MetaRocq.Template Require Import Loader.',
      'From SelvedgePathAudit Require Import Scan.',
      'Import ListNotations.',
      'Open Scope string_scope.',
      ...names.map(name => `Require ${name}.`),
      `MetaRocq Run (scan_project [${names.map(name => JSON.stringify(name)).join(';')}]).`,
    ].join('\n');
    await writeFile(job, source + '\n');
    let lines;
    try {
      lines = (await run('rocq', ['compile', ...flags, job])).split(/\r?\n/);
    } catch (error) {
      // DEFENSE: MetaRocq cannot quote sort-polymorphic terms in TaskGraphSemantics.
      // Isolate the actual unsupported module so every other module is checked.
      if (!error.message.includes('Quoting sort polymorphic instances not yet supported.')) throw error;
      if (batch.length === 1) {
        unavailable.push({ file: batch[0], reason: 'MetaRocq cannot quote sort-polymorphic terms.' });
        return;
      }
      const half = Math.floor(batch.length / 2);
      await scanBatch(batch.slice(0, half));
      await scanBatch(batch.slice(half));
      return;
    }

    const filesByModule = new Map(names.map((name, i) => [name, batch[i]]));
    const seen = new Set();
    for (let index = 0; index < lines.length; index++) {
      const [record, name, producer, consumer, form] = lines[index].split(' ');
      if (record === 'MODULE') {
        seen.add(name);
      } else if (record === 'HIT') {
        const file = filesByModule.get(name.slice(0, name.lastIndexOf('.')));
        const count = lines[++index];
        if (!file || !/^\d+$/.test(count) || !['let', 'nested'].includes(form)) {
          throw new Error(`Malformed Rocq finding for ${name} in ${job}`);
        }
        const uses = Number(count);
        const rule = validatedRules.get(`${producer} → ${consumer}`);
        findings.push({
          file, function: name, producer, consumer, via: form, uses,
          classification: rule ? 'known rewrite' : 'candidate',
          ...(rule === undefined ? {} : { rule }),
        });
      }
    }
    if (seen.size !== names.length || names.some(name => !seen.has(name))) throw new Error(`Incomplete Rocq results in ${job}`);
    scanned += seen.size;
  }

  const batches = [];
  for (let index = 0; index < filenames.length; index += 24) batches.push(filenames.slice(index, index + 24));
  let current = 0;
  await Promise.all(Array.from({ length: 4 }, async () => {
    while (current < batches.length) await scanBatch(batches[current++]);
  }));

  const sources = new Map();
  for (const hit of findings) {
    if (!sources.has(hit.file)) sources.set(hit.file, (await readFile(path.join(root, hit.file), 'utf8')).split('\n'));
    const short = hit.function.split('.').at(-1);
    const declaration = sources.get(hit.file).findIndex(line =>
      /^\s*(?:(?:Local|Global)\s+)?(?:Definition|Fixpoint|CoFixpoint|Let)\s+([\w']+)/.exec(line)?.[1] === short);
    if (declaration >= 0) hit.line = declaration + 1;
  }
  return { modules: scanned, unavailable, findings };
}

async function main() {
  await mkdir(path.join(root, '.workpad'), { recursive: true });
  const directory = await mkdtemp(path.join(root, '.workpad', 'path-audit-'));
  const rocqFiles = (await sourceFiles()).filter(file =>
    !file.startsWith('theories/Derive/') && !file.startsWith('theories/ThirdParty/'));
  const listed = await run('git', ['ls-files', '-z', 'host', 'remote', 'relay/src', 'plugins']);
  const javascriptFiles = listed.split('\0').filter(file =>
    /\.(?:mjs|cjs|js|ts)$/.test(file) && !/\/(?:generated|vendor)\//.test(file));
  const javascript = scanJavaScript(javascriptFiles.map(file => path.join(root, file)));
  for (const hit of javascript.findings) hit.file = path.relative(root, hit.file);

  // Reuse the proof-only build to check source/object fingerprints before quotation.
  await build({ selected: [], check: true });
  const rocq = await scanRocq(directory, rocqFiles);
  rocq.findings.sort((a, b) => a.function.localeCompare(b.function));
  rocq.unavailable.sort((a, b) => a.file.localeCompare(b.file));
  const filename = path.join(directory, 'report.json');
  await writeFile(filename, JSON.stringify({ rocq, javascript }, null, 2) + '\n');
  console.log(`Rocq ${rocq.modules}/${rocqFiles.length} modules, ${rocq.findings.length} matches`);
  console.log(`JavaScript/TypeScript ${javascript.files} files, ${javascript.findings.length} candidates`);
  for (const item of rocq.unavailable) console.log(`Skipped ${item.file}. ${item.reason}`);
  console.log(path.relative(root, filename));
}

await main();
