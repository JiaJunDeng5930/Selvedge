import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { compiler } from './toolchain.mjs';
import { prepareUiVerification } from './ui-verification.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

// The pinned compiler may successfully check programs that use unsafe/foreign
// definitions. Such a report is acceptable for MAIN's IO boundary, never PROOF.
// One shared, fail-closed gate is used by checking, builds and cached builds.
export function verifyProof({ cwd = root, entry, timeout = 60_000 } = {}) {
  entry ??= prepareUiVerification(cwd).entry;
  const result = spawnSync(compiler(), [entry, '--check-only'], {
    cwd, encoding: 'utf8', timeout, maxBuffer: 4 * 1024 * 1024,
    env: { ...process.env, BEND_NO_TELEMETRY: '1', NO_COLOR: '1' },
  });
  if (result.error) throw new Error(`Pure proof gate could not check ${entry}`, { cause: result.error });
  const report = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  if (result.status !== 0 || result.stdout.trim() !== 'ALL PROOFS CHECK\nUse --verdict for mathematical validity.' || result.stderr.trim() !== '') {
    throw new Error(`Pure proof gate rejected ${entry}:\n${report.trim()}`);
  }
  return result.stdout.trim();
}

// MAIN's three explicit IO assumptions are a separate boundary, never pure proof
// evidence. Bend 2.0.34 reports these well-typed promises with a failing verdict.
export function verifyNativeEntry({ cwd = root, timeout = 60_000 } = {}) {
  const result = spawnSync(compiler(), ['MAIN.bend', '--check-only'], {
    cwd, encoding: 'utf8', timeout, maxBuffer: 4 * 1024 * 1024,
    env: { ...process.env, BEND_NO_TELEMETRY: '1', NO_COLOR: '1' },
  });
  if (result.error) throw new Error('Native entry gate could not check MAIN.bend', { cause: result.error });
  const boundary = 'SOME PROOFS FAIL\nError: 3 defs rely on unsafe or foreign code:\n- Host.receive\n- serve\n- main';
  if (result.status !== 1 || result.stdout.trim() !== '' || result.stderr.trim() !== boundary) {
    throw new Error(`Native entry gate rejected MAIN.bend:\n${result.stdout}${result.stderr}`);
  }
  return 'Native entry types check with the declared IO assumptions.';
}
