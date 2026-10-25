import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

/** Drive the same authorization URL that the CLI asks a human to open. */
export async function loginThroughCli(directory, issuer) {
  const child = spawn(process.execPath,
    [fileURLToPath(new URL('../../host/cli.mjs', import.meta.url)), '--home', directory, 'login'],
    { stdio: ['ignore', 'pipe', 'pipe'] });
  let stderr = '', authorization;
  child.stderr.on('data', chunk => { stderr += chunk; });
  const lines = createInterface({ input: child.stdout });
  lines.on('line', line => {
    const match = line.match(/http:\/\/127\.0\.0\.1:\d+\/authorize\?\S+/);
    if (match && !authorization) {
      const url = new URL(match[0]);
      if (url.origin !== issuer) throw new Error('CLI selected an unexpected authorization issuer');
      authorization = fetch(url);
    }
  });
  const timer = setTimeout(() => child.kill('SIGKILL'), 10000);
  try {
    const code = await new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('close', resolve);
    });
    if (authorization) await authorization;
    return { code, stderr, opened: Boolean(authorization) };
  } finally {
    clearTimeout(timer);
    lines.close();
  }
}
