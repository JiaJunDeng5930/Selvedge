import { Miniflare, Log, LogLevel, convertV4MiniflareOptions } from 'miniflare';
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

export async function startRelay({ enrollmentToken = 'local-test-enrollment-secret' } = {}) {
  const bundle = await build({ entryPoints: [fileURLToPath(new URL('../src/worker.mjs', import.meta.url))],
    bundle: true, format: 'esm', platform: 'browser', write: false, target: 'es2022' });
  const runtime = new Miniflare(convertV4MiniflareOptions({
    name: 'selvedge-remote-relay',
    modules: true,
    script: bundle.outputFiles[0].text,
    compatibilityDate: '2026-10-16',
    host: '127.0.0.1', port: 0,
    bindings: { RELAY_ENROLLMENT_TOKEN: enrollmentToken, REMOTE_LOCAL_TEST: 'true' },
    durableObjects: { REMOTE_HOSTS: { className: 'RemoteHostRelay', useSQLite: true } },
    unsafeInspectDurableObjects: true,
    log: new Log(LogLevel.ERROR),
  }));
  try {
    const ready = await runtime.ready;
    return {
      url: ready.origin,
      close: () => runtime.dispose(),
      hibernate: hostId => runtime.unsafeEvictDurableObject('selvedge-remote-relay', 'RemoteHostRelay', {
        name: hostId, webSockets: 'hibernate',
      }),
    };
  } catch (error) { await runtime.dispose(); throw error; }
}
