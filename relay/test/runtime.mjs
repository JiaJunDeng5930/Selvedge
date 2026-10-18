import { Miniflare, Log, LogLevel, convertV4MiniflareOptions } from 'miniflare';
import { build } from 'esbuild';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
export { default as WebSocket } from 'ws';

export async function startRelay({ enrollmentToken = 'local-test-enrollment-secret' } = {}) {
  const configurationURL = new URL('../wrangler.jsonc', import.meta.url);
  const configuration = JSON.parse(await readFile(configurationURL, 'utf8'));
  const sqliteClasses = new Set(configuration.migrations.flatMap(migration => migration.new_sqlite_classes ?? []));
  const objects = Object.fromEntries(configuration.durable_objects.bindings.map(binding =>
    [binding.name, { className: binding.class_name, useSQLite: sqliteClasses.has(binding.class_name) }]));
  const bundle = await build({ entryPoints: [fileURLToPath(new URL(configuration.main, configurationURL))],
    bundle: true, format: 'esm', platform: 'browser', write: false, target: 'es2022' });
  const runtime = new Miniflare(convertV4MiniflareOptions({
    name: configuration.name,
    modules: true,
    script: bundle.outputFiles[0].text,
    compatibilityDate: configuration.compatibility_date,
    host: '127.0.0.1', port: 0,
    bindings: { RELAY_ENROLLMENT_TOKEN: enrollmentToken, REMOTE_LOCAL_TEST: 'true' },
    durableObjects: objects,
    unsafeInspectDurableObjects: true,
    log: new Log(LogLevel.ERROR),
  }));
  try {
    const ready = await runtime.ready;
    return {
      url: ready.origin,
      close: () => runtime.dispose(),
      hibernate: hostId => runtime.unsafeEvictDurableObject(configuration.name, objects.REMOTE_HOSTS.className, {
        name: hostId, webSockets: 'hibernate',
      }),
    };
  } catch (error) { await runtime.dispose(); throw error; }
}
