import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const expectedVersion = readFileSync(new URL('../bend-version', import.meta.url), 'utf8').trim();
const local = fileURLToPath(new URL('../.build/bend/bin/bend', import.meta.url));

// The pinned verifier recursively compares finite lowered instruction terms.
// Configure compiler children only; leave the host, tests and heap policy alone.
export function compilerEnvironment() {
  return { ...process.env, BUN_JSC_maxPerThreadStackUsage: '14680064' };
}

export function compilerInvocation(executable, args) {
  return {
    command: '/bin/sh',
    args: ['-c', [
      '# DEFENSE: A restricted shell can refuse the 16 MiB stack required by the pinned verifier; fail before starting it.',
      'if ! ulimit -S -s 16384; then',
      '  printf "%s\\n" "Bend compiler requires a 16 MiB OS stack" >&2',
      '  exit 78',
      'fi',
      'exec "$@"',
    ].join('\n'), 'selvedge-compiler', executable, ...args],
  };
}

export function compiler() {
  // DEFENSE: A developer can invoke this build script with Node even though compiler execution requires Bun.
  if (!process.versions.bun) throw new Error('Selvedge requires Bun');
  const binary = existsSync(local) ? local : 'bend';
  const invocation = compilerInvocation(binary, ['version']);
  const version = spawnSync(invocation.command, invocation.args, { encoding: 'utf8', env: { ...compilerEnvironment(), BEND_NO_TELEMETRY: '1' } });
  // DEFENSE: OS process limits or a missing launcher can prevent the version subprocess from starting.
  if (version.error) throw version.error;
  // DEFENSE: The installed compiler can be absent, fail its version command or differ from the pinned Bend release.
  if (version.status !== 0 || version.stdout.trim() !== `bend ${expectedVersion}`) {
    throw new Error(`Bend ${expectedVersion} is required. Run bash scripts/install-bend.sh to install the pinned workspace compiler.${version.stderr.trim() ? ` ${version.stderr.trim()}` : ''}`);
  }
  return binary;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(`Using ${compiler()} (${expectedVersion})`);
}
