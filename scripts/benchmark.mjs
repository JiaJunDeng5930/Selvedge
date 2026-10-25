import { readdir, readFile, writeFile, rm, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { collectBenchmarkProvenance, runRuntimeBenchmark } from './runtime-benchmark.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

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
  return samples.reduce((sum, value) => sum + value, 0);
}

async function measured(label) {
  const started = performance.now();
  const child = spawn(process.execPath, ['scripts/build.mjs'], { cwd: root, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '', peakPssKiB = 0, active = true;
  child.stdout.on('data', chunk => output += chunk);
  child.stderr.on('data', chunk => output += chunk);
  const sampler = (async () => {
    while (active) {
      peakPssKiB = Math.max(peakPssKiB, await residentTree(child.pid));
      await new Promise(resolve => setTimeout(resolve, 50));
    }
  })();
  const { code, finished } = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', code => resolve({ code, finished: performance.now() }));
  });
  active = false;
  await sampler;
  await writeFile(path.join(root, `.workpad/benchmark-${label}.log`), output);
  if (code !== 0) throw new Error(`Benchmark ${label} failed; inspect .workpad/benchmark-${label}.log`);
  const result = {
    scenario: label,
    seconds: (finished - started) / 1000,
    peakSummedPssKiB: peakPssKiB,
    checkedModules: Number(/Rocq: (\d+) checked/.exec(output)?.[1]),
    extractedTargets: [...output.matchAll(/^extracted (\w+)$/gm)].map(match => match[1]),
  };
  console.log(JSON.stringify(result));
  return result;
}

async function runBuildBenchmark({ provenance, requestedFiles }) {
  await mkdir(path.join(root, '.workpad'), { recursive: true });
  for (const filename of await paths('theories')) {
    if (/\.(vo|vos|vok|glob)$|\/\..*\.aux$/.test(filename)) await rm(path.join(root, filename));
  }
  for (const filename of ['.build/build-state.json', '.build/extracted', '.lia.cache', '.nia.cache']) {
    await rm(path.join(root, filename), { recursive: true, force: true });
  }
  const results = [await measured('clean'), await measured('unchanged')];
  const changes = requestedFiles.length ? requestedFiles : [
    'theories/Browser/Layout.v',
    'theories/Kernel/Commands.v',
    'theories/Foundation/Schema.v',
    'theories/Browser/LayoutProof.v',
  ];
  for (const [index, filename] of changes.entries()) {
    const original = await readFile(path.join(root, filename));
    try {
      await writeFile(path.join(root, filename), Buffer.concat([original, Buffer.from('\n(* Temporary build-dependency benchmark mutation. *)\n')]));
      results.push(await measured(`change-${index + 1}`));
      results.at(-1).source = filename;
    } finally {
      await writeFile(path.join(root, filename), original);
      await measured(`restore-${index + 1}`);
    }
  }
  results.push(await measured('restored'));
  const report = {
    provenance,
    sampling: 'sum of process-tree PSS, sampled every 50 ms; Linux',
    measurements: results,
  };
  await writeFile(path.join(root, '.workpad/build-benchmark.json'), `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

function integerArgument(value, name) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error(`${name} must be a positive integer`);
  return parsed;
}

function parseArguments(args) {
  const parsed = { scenario: null, quick: false, tasks: undefined, historyTurns: undefined, messageBytes: undefined, requestedFiles: [], help: false };
  for (let index = 0; index < args.length; index++) {
    const argument = args[index];
    const value = name => {
      if (index + 1 >= args.length) throw new Error(`${name} requires a value`);
      return args[++index];
    };
    if (argument === '--help' || argument === '-h') parsed.help = true;
    else if (argument === '--scenario') {
      parsed.scenario = value(argument);
      if (!['all', 'build', 'runtime'].includes(parsed.scenario)) throw new Error('--scenario must be all, build, or runtime');
    } else if (argument === '--quick') parsed.quick = true;
    else if (argument === '--tasks') {
      parsed.tasks = value(argument).split(',').map(item => integerArgument(item, '--tasks'));
    } else if (argument === '--history-turns') parsed.historyTurns = integerArgument(value(argument), argument);
    else if (argument === '--message-bytes') parsed.messageBytes = integerArgument(value(argument), argument);
    else if (argument.startsWith('-')) throw new Error(`Unknown benchmark option: ${argument}`);
    else parsed.requestedFiles.push(argument);
  }
  parsed.scenario ??= parsed.quick ? 'runtime' : 'all';
  if (parsed.scenario === 'runtime' && parsed.requestedFiles.length > 0) {
    throw new Error('Positional source files apply only to the build scenario');
  }
  if (parsed.scenario === 'build' && (parsed.tasks || parsed.historyTurns || parsed.messageBytes)) {
    throw new Error('Runtime workload options require --scenario runtime or --scenario all');
  }
  return parsed;
}

const help = `Usage: bun scripts/benchmark.mjs [options] [source-files...]\n\n` +
  `Options:\n` +
  `  --scenario all|build|runtime  Select measurements (default: all)\n` +
  `  --quick                      Run a small runtime-only workload by default\n` +
  `  --tasks 17,65                Runtime task counts (1 plus a multiple of four)\n` +
  `  --history-turns 32           User messages per root task\n` +
  `  --message-bytes 1024         Bytes in each user message\n` +
  `  -h, --help                   Show this help\n`;

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.help) { console.log(help); return; }
  const provenance = await collectBenchmarkProvenance();
  if (options.scenario === 'runtime' || options.scenario === 'all') {
    const report = await runRuntimeBenchmark({ ...options, provenance });
    console.log(JSON.stringify({ scenario: 'runtime', measurements: report.measurements }));
  }
  if (options.scenario === 'build' || options.scenario === 'all') {
    const report = await runBuildBenchmark({ provenance, requestedFiles: options.requestedFiles });
    console.log(JSON.stringify({ scenario: 'build', measurements: report.measurements.length }));
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
