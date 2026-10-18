import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { compiler, compilerCommand } from './toolchain.mjs';
import { compilerEnvironment } from './compiler-memory.mjs';
import { prepareUiVerification } from './ui-verification.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

// The pinned compiler may successfully check programs that use unsafe/foreign
// definitions. Such a report is acceptable for MAIN's IO boundary, never PROOF.
// Standalone CLI gate. Builds apply this same pinned verdict to their fresh prefix.
export function verifyProof({ cwd = root, entry, timeout = 300_000 } = {}) {
  entry ??= prepareUiVerification(cwd).entry;
  const result = spawnSync(compiler(), [entry, '--check-only'], {
    cwd, encoding: 'utf8', timeout, maxBuffer: 4 * 1024 * 1024,
    env: compilerEnvironment({ NO_COLOR: '1', NODE_OPTIONS: '' }),
  });
  if (result.error) throw new Error(`Pure proof gate could not check ${entry}`, { cause: result.error });
  const report = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  if (result.status !== 0 || result.stdout.trim() !== 'ALL PROOFS CHECK\nUse --verdict for mathematical validity.' || result.stderr.trim() !== '') {
    throw new Error(`Pure proof gate rejected ${entry} (status: ${result.status ?? 'none'}, signal: ${result.signal ?? 'none'}):\n${report.trim()}`);
  }
  return result.stdout.trim();
}

// MAIN's three explicit IO assumptions are a separate boundary, never pure proof
// evidence. Bend 2.0.34 reports these well-typed promises with a failing verdict.
export async function verifyNativeEntry({ cwd = root, timeout = 300_000 } = {}) {
  const [command, ...args] = await compilerCommand();
  const result = spawnSync(command, [...args, 'MAIN.bend', '--check-only'], {
    cwd, encoding: 'utf8', timeout, maxBuffer: 4 * 1024 * 1024,
    env: compilerEnvironment({ NO_COLOR: '1', NODE_OPTIONS: '' }),
  });
  if (result.error) throw new Error('Native entry gate could not check MAIN.bend', { cause: result.error });
  const boundary = 'SOME PROOFS FAIL\nError: 3 defs rely on unsafe or foreign code:\n- Host.receive\n- serve\n- main';
  if (result.status !== 1 || result.stdout.trim() !== '' || result.stderr.trim() !== boundary) {
    throw new Error(`Native entry gate rejected MAIN.bend (status: ${result.status ?? 'none'}, signal: ${result.signal ?? 'none'}):\n${result.stdout}${result.stderr}`);
  }
  return 'Native entry types check with the declared IO assumptions.';
}
