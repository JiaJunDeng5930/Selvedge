import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, mkdir, writeFile, stat, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { compiler, expectedVersion } from './toolchain.mjs';
import { checkBundle } from './import-stdlib.mjs';
import { checkRelations } from './import-relations.mjs';
import { checkMaps } from './import-maps.mjs';
import { verifyProof } from './verify-proof.mjs';
import { checkComponents, bendSources } from './check-components.mjs';
import { compileJavaScript } from './compile-javascript.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

async function compileEntry(entry, output, force) {
  // Root entry definitions are public wrappers; import aliases are not compiler names.
  const source = await readFile(path.join(root, entry), 'utf8');
  const names = [...source.matchAll(/^def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/gm)].map(match => match[1]);
  if (!names.length) throw new Error(`No public Bend wrappers in ${entry}`);
  if (force) await rm(path.join(root, `${output}.json`), { force: true });
  return compileJavaScript({ entry, exports: Object.fromEntries(names.map(name => [name, name])), output });
}

export async function build({ native = false, force = false } = {}) {
  console.log(await checkComponents(root));
  const bend = compiler();
  await checkBundle();
  await checkRelations();
  await checkMaps();
  console.log(verifyProof({ cwd: root }));
  console.log(verifyProof({ cwd: root, entry: 'webui/PROOF.bend' }));

  const kernel = await compileEntry('KERNEL.bend', '.build/kernel-model.mjs', force);
  console.log(`Bend JavaScript kernel ${kernel.cached ? 'is current' : 'built'} (${kernel.fingerprint.slice(0, 12)}).`);
  const browser = await compileEntry('BROWSER.bend', 'host/public/generated/browser-model.mjs', force);
  console.log(`Bend JavaScript browser ${browser.cached ? 'is current' : 'built'} (${browser.fingerprint.slice(0, 12)}).`);

  const inputs = await bendSources(root);
  const journalFormat = 'selvedge-bend-journal-2';
  const backend = 'bend-javascript';
  const kernelManifest = JSON.parse(await readFile(`${kernel.output}.json`, 'utf8'));
  const javascriptCompiler = kernelManifest.compiler;
  const hash = createHash('sha256').update(`Bend ${expectedVersion}\0${journalFormat}\0${backend}\0`)
    .update(JSON.stringify(javascriptCompiler)).update('\0').update(kernel.fingerprint).update('\0').update(browser.fingerprint).update('\0');
  for (const name of inputs) hash.update(name).update('\0').update(await readFile(path.join(root, name))).update('\0');
  const fingerprint = hash.digest('hex');
  const directory = path.join(root, '.build');
  await mkdir(directory, { recursive: true });
  // Publish journal identity only after both production libraries have compiled successfully.
  await writeFile(path.join(directory, 'kernel.json'), JSON.stringify({
    format: journalFormat, compiler: expectedVersion, fingerprint, backend, javascriptCompiler,
    sources: inputs, models: { kernel: kernel.fingerprint, browser: browser.fingerprint },
  }, null, 2) + '\n');

  if (native) {
    let previous;
    try { previous = JSON.parse(await readFile(path.join(directory, 'native.json'), 'utf8')); } catch {}
    let binaryExists = false;
    try { binaryExists = (await stat(path.join(directory, 'selvedge-kernel'))).isFile(); } catch {}
    if (previous?.fingerprint !== fingerprint || !binaryExists || force) {
      const result = spawnSync(bend, ['MAIN.bend', '-o', '.build/selvedge-kernel'], { cwd: root, stdio: 'inherit', env: { ...process.env, BEND_NO_TELEMETRY: '1' } });
      if (result.error) throw result.error;
      if (result.status !== 0) throw new Error(`Native Bend compilation failed (${result.status})`);
      await writeFile(path.join(directory, 'native.json'), JSON.stringify({ compiler: expectedVersion, fingerprint }, null, 2) + '\n');
      console.log(`Built optional native Bend kernel ${fingerprint.slice(0, 12)}.`);
    } else console.log(`Optional native Bend kernel is current (${fingerprint.slice(0, 12)}).`);
  }
  return { kernel, browser, fingerprint };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await build({ native: process.argv.includes('--native'), force: process.argv.includes('--force') });
}
