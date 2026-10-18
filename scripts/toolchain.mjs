import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const expectedVersion = readFileSync(new URL('../bend-version', import.meta.url), 'utf8').trim();
const local = fileURLToPath(new URL('../.build/bend/bin/bend', import.meta.url));

// These settings affect compiler children only. Full collections reclaim the
// checker's temporary proof terms; 30% growth balances collection cost and memory.
// The threshold (MiB) selects these factors instead of JSC's large-RAM heuristic.
export function compilerEnvironment() {
  return {
    ...process.env,
    BUN_JSC_useGenerationalGC: 'false',
    BUN_JSC_heapGrowthFunctionThresholdInMB: '1048576',
    BUN_JSC_smallHeapGrowthFactor: '1.3',
    BUN_JSC_mediumHeapGrowthFactor: '1.3',
    BUN_JSC_largeHeapGrowthFactor: '1.3',
    // compilerInvocation reserves a 16 MiB OS stack before starting this VM.
    BUN_JSC_maxPerThreadStackUsage: '14680064',
  };
}

// exec retains the compiler PID and process group used by timeout/cancellation.
// Arguments stay positional, so paths and source arguments are never shell code.
export function compilerInvocation(executable, args) {
  return {
    command: '/bin/sh',
    args: ['-c', [
      'if ! ulimit -S -s 16384; then',
      '  printf "%s\\n" "Bend compiler requires a 16 MiB OS stack" >&2',
      '  exit 78',
      'fi',
      'exec "$@"',
    ].join('\n'), 'selvedge-compiler', executable, ...args],
  };
}

export function compiler() {
  if (!process.versions.bun) throw new Error('Selvedge requires Bun');
  const binary = existsSync(local) ? local : 'bend';
  const invocation = compilerInvocation(binary, ['version']);
  const version = spawnSync(invocation.command, invocation.args, { encoding: 'utf8', env: { ...compilerEnvironment(), BEND_NO_TELEMETRY: '1' } });
  if (version.error || version.status !== 0 || version.stdout.trim() !== `bend ${expectedVersion}`) {
    throw new Error(`Bend ${expectedVersion} is required. Run bash scripts/install-bend.sh to install the pinned workspace compiler.${version.stderr?.trim() ? ` ${version.stderr.trim()}` : ''}`);
  }
  return binary;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(`Using ${compiler()} (${expectedVersion})`);
}
