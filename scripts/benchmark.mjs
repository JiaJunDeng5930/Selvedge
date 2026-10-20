import { readdir, readFile, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { root } from './build.mjs';

async function paths(directory) {
  return (await Promise.all((await readdir(path.join(root, directory), { withFileTypes: true })).map(entry => {
    const filename = `${directory}/${entry.name}`;
    return entry.isDirectory() ? paths(filename) : [filename];
  }))).flat();
}
async function residentTree(pid) {
  const pids = (await readdir('/proc')).filter(name => /^\d+$/.test(name));
  const entries = await Promise.all(pids.map(async name => {
    try {
      const text = await readFile(`/proc/${name}/stat`, 'utf8');
      const fields = text.slice(text.lastIndexOf(')') + 2).split(' ');
      return { pid: Number(name), parent: Number(fields[1]) };
    } catch (error) {
      // DEFENSE: A measured child can exit while its /proc directory is being sampled.
      if (error.code === 'ENOENT' || error.code === 'ESRCH') return null;
      throw error;
    }
  }));
  const owned = new Set([pid]);
  let changed;
  do {
    changed = false;
    for (const entry of entries) if (entry && owned.has(entry.parent) && !owned.has(entry.pid)) {
      owned.add(entry.pid); changed = true;
    }
  } while (changed);
  const samples = await Promise.all([...owned].map(async processId => {
    try {
      const text = await readFile(`/proc/${processId}/smaps_rollup`, 'utf8');
      const sample = /^Pss:\s+(\d+) kB$/m.exec(text);
      // DEFENSE: A missing kernel measurement cannot be reported as zero memory usage.
      if (!sample) throw new Error(`Missing PSS measurement for process ${processId}`);
      return Number(sample[1]);
    } catch (error) {
      // DEFENSE: Children can exit between ancestry sampling and memory sampling.
      if (error.code === 'ENOENT' || error.code === 'ESRCH') return 0;
      throw error;
    }
  }));
  return samples.reduce((sum,value) => sum + value, 0);
}
async function measured(label) {
  const started = performance.now();
  const child = spawn(process.execPath, ['scripts/build.mjs'], { cwd: root, stdio: ['ignore','pipe','pipe'] });
  let output = '', peakPssKiB = 0, active = true;
  child.stdout.on('data', chunk => output += chunk);
  child.stderr.on('data', chunk => output += chunk);
  const sampler = (async () => {
    while (active) {
      peakPssKiB = Math.max(peakPssKiB, await residentTree(child.pid));
      await new Promise(resolve => setTimeout(resolve, 50));
    }
  })();
  const { code, finished } = await new Promise((resolve,reject) => {
    child.once('error',reject);
    child.once('close',code => resolve({code,finished:performance.now()}));
  });
  active = false;
  await sampler;
  await writeFile(path.join(root, `.workpad/benchmark-${label}.log`), output);
  if (code !== 0) throw new Error(`Benchmark ${label} failed; inspect .workpad/benchmark-${label}.log`);
  const result = { scenario: label, seconds: (finished-started)/1000, peakSummedPssKiB: peakPssKiB,
    checkedModules: Number(/Rocq: (\d+) checked/.exec(output)?.[1]),
    extractedTargets: [...output.matchAll(/^extracted (\w+)$/gm)].map(match => match[1]) };
  console.log(JSON.stringify(result));
  return result;
}
await import('node:fs/promises').then(({mkdir}) => mkdir(path.join(root,'.workpad'),{recursive:true}));
for (const filename of await paths('theories')) if (/\.(vo|vos|vok|glob)$|\/\..*\.aux$/.test(filename)) await rm(path.join(root,filename));
for (const filename of ['.build/build-state.json','.build/extracted']) await rm(path.join(root,filename),{recursive:true,force:true});
const results = [await measured('clean'), await measured('unchanged')];
const requested = process.argv.slice(2);
const changes = requested.length ? requested : ['theories/Browser/Native.v','theories/Kernel/Commands.v','theories/Foundation/Schema.v','theories/Browser/NativeProof.v'];
for (const [index,filename] of changes.entries()) {
  const original = await readFile(path.join(root,filename));
  try {
    await writeFile(path.join(root,filename),Buffer.concat([original,Buffer.from('\n(* Temporary build-dependency benchmark mutation. *)\n')]));
    results.push(await measured(`change-${index+1}`));
    results.at(-1).source = filename;
  } finally {
    await writeFile(path.join(root,filename),original);
    await measured(`restore-${index+1}`);
  }
}
// Restore checked artifacts to the unchanged source before handing the workspace back.
results.push(await measured('restored'));
await writeFile(path.join(root,'.workpad/build-benchmark.json'),JSON.stringify({sampling:'sum of process-tree PSS, sampled every 50 ms; Linux',results},null,2)+'\n');
