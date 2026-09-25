import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { compiler } from './toolchain.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

// The pinned compiler may successfully check programs that use unsafe/foreign
// definitions. Such a report is acceptable for MAIN's IO boundary, never PROOF.
// One shared, fail-closed gate is used by checking, builds and cached builds.
export function verifyProof({ cwd = root, entry = 'PROOF.bend', timeout = 60_000 } = {}) {
  const result = spawnSync(compiler(), [entry, '--check-only'], {
    cwd, encoding: 'utf8', timeout, maxBuffer: 4 * 1024 * 1024,
    env: { ...process.env, BEND_NO_TELEMETRY: '1', NO_COLOR: '1' },
  });
  if (result.error) throw new Error(`Pure proof gate could not check ${entry}`, { cause: result.error });
  const report = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  if (result.status !== 0 || result.stdout.trim() !== 'All terms check.' || result.stderr.trim() !== '') {
    throw new Error(`Pure proof gate rejected ${entry}:\n${report.trim()}`);
  }
  return result.stdout.trim();
}
