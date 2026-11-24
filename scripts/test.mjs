import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { build, root } from './build.mjs';
import { runTestProcess, terminateTestProcessGroup } from './test-process.mjs';
import { buildModel } from '../plugins/selvedge-chatgpt/scripts/build-model.mjs';

const testDirectory = new URL('../tests/', import.meta.url);

async function startBrowserForSuite(tests) {
  const sources = await Promise.all(tests.map(name => readFile(new URL(name, testDirectory), 'utf8')));
  if (!sources.some(source => source.includes('./fixtures/browser.mjs'))) return;

  const { launchChromium, startChromiumServer } = await import('../tests/fixtures/chromium.mjs');
  let server;
  try {
    server = await startChromiumServer();
    const browser = await launchChromium(server.wsEndpoint());
    try {
      await browser.newPage();
    } finally {
      await browser.close();
    }
    return server;
  } catch (error) {
    await server?.close();
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`Browser test setup failed before running the selected suite.\n${detail}`);
  }
}

export async function runTests(buildResult, selected = process.argv.slice(2)) {
  const files = (await readdir(testDirectory)).filter(name => name.endsWith('.test.mjs')).sort();
  const tests = selected.length ? files.filter(name => selected.includes(name) || selected.includes(`tests/${name}`)) : files;
  if (!tests.length) throw new Error('No end-to-end tests selected');
  const browserServer = await startBrowserForSuite(tests);
  const active = new Set();
  let interrupted = false;
  const handlers = ['SIGINT', 'SIGTERM'].map(signal => {
    const handler = () => {
      interrupted = true;
      process.exitCode = 1;
      for (const child of active) terminateTestProcessGroup(child);
    };
    process.on(signal, handler);
    return [signal, handler];
  });
  try {
    const completed = buildResult ?? await build();
    if (buildResult && !completed.checked) throw new Error('Repository verification requires its checked build result');
    if (!['kernel', 'host', 'browser', 'interaction'].every(name => completed.targets.includes(name))) {
      throw new Error('End-to-end tests require all production build targets');
    }
    await buildModel({ buildResult: completed });
    const env = { ...process.env };
    if (browserServer) env.SELVEDGE_TEST_BROWSER_ENDPOINT = browserServer.wsEndpoint();
    // Bound a hung test without treating a complete browser workflow as a
    // 30-second performance requirement. Individual waits keep their deadlines.
    const result = await runTestProcess('Selvedge end-to-end tests', [process.execPath, 'test', '--timeout', '120000', ...tests.map(name => `tests/${name}`)], { cwd: root, active, env });
    const output = `${result.out}\n${result.err}`;
    const passes = [...output.matchAll(/^\s*(\d+) pass\s*$/gm)];
    const failures = [...output.matchAll(/^\s*(\d+) fail\s*$/gm)];
    const runs = [...output.matchAll(/^Ran (\d+) tests? across (\d+) files?\./gm)];
    const complete = passes.length === 1 && failures.length === 1 && runs.length === 1
      && Number(passes[0][1]) === Number(runs[0][1]) && Number(failures[0][1]) === 0
      && Number(runs[0][1]) > 0 && Number(runs[0][2]) > 0;
    // DEFENSE: A test module can exit zero before running tests; require Bun's complete successful footer.
    if (interrupted || result.exitCode !== 0 || result.signal || !complete) {
      throw new Error(`End-to-end suite failed: exit=${result.exitCode}, signal=${result.signal ?? 'none'}, completeFooter=${complete}`);
    }
    return completed;
  } finally {
    for (const [signal, handler] of handlers) process.off(signal, handler);
    for (const child of active) terminateTestProcessGroup(child);
    await browserServer?.close();
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await runTests();
