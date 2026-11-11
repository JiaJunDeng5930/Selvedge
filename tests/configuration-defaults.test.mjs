import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { defaultConfig, loadConfig } from '../host/config.mjs';
import { main } from '../host/cli.mjs';
import { home } from './support.mjs';

test('fresh CLI configuration has no demo profile and existing echo profiles remain configured', async t => {
  const freshHome = await home(t);
  await main(['--home', freshHome, 'init']);

  const initialized = JSON.parse(await readFile(path.join(freshHome, 'config.json'), 'utf8'));
  assert.deepEqual(initialized.profiles, {});
  assert.deepEqual((await loadConfig({ home: freshHome })).config.profiles, {});

  const configuredHome = await home(t);
  const explicit = { ...defaultConfig, profiles: { demo: { provider: 'echo', model: 'echo' } } };
  await writeFile(path.join(configuredHome, 'config.json'), JSON.stringify(explicit));
  const { config } = await loadConfig({ home: configuredHome });
  assert.deepEqual(Object.keys(config.profiles), ['demo']);
  assert.equal(config.profiles.demo.provider, 'echo');
  assert.equal(config.profiles.demo.model, 'echo');
});
