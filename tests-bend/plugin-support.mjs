import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import { defaultConfig, validateConfig } from '../host/config.mjs';

export const fixture = fileURLToPath(new URL('./fixtures/plugin.mjs', import.meta.url));
export const settings = (directory, name, mode = 'normal', extra = {}) => ({
  command: process.execPath, args: [fixture], timeout_ms: 1000,
  env: { PLUGIN_NAME: name, PLUGIN_MODE: mode, PLUGIN_LOG: path.join(directory, 'plugins.jsonl'),
    PLUGIN_JOURNAL: path.join(directory, 'state', 'journal.sqlite'), ...extra },
});
export async function logs(directory) {
  try { return (await readFile(path.join(directory, 'plugins.jsonl'), 'utf8')).trim().split('\n').filter(Boolean).map(JSON.parse); }
  catch (error) { if (error.code === 'ENOENT') return []; throw error; }
}
export function journal(directory) {
  const database = new DatabaseSync(path.join(directory, 'state', 'journal.sqlite'), { readOnly: true });
  try { return database.prepare('SELECT seq, input, decision FROM journal ORDER BY seq').all()
    .map(row => ({ sequence: row.seq, input: JSON.parse(row.input), ...JSON.parse(row.decision) })); }
  finally { database.close(); }
}
export async function waitFor(read, check, message) {
  const deadline = Date.now() + 5000;
  let value;
  do { value = await read(); if (check(value)) return value; await delay(10); } while (Date.now() < deadline);
  throw new Error(`${message}: ${JSON.stringify(value)}`);
}
export function configure(endpoint, plugins) {
  return validateConfig({ ...defaultConfig, profiles: { live: { provider: 'responses', model: 'fixture', endpoint, api_key_env: 'PATH' } }, plugins });
}
export const call = (name, id, arguments_) => ({ type: 'function_call', name, call_id: id, arguments: JSON.stringify(arguments_) });
export const answer = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Done' }] }];
