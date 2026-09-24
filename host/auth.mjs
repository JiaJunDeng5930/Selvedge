import { DatabaseSync } from 'node:sqlite';
import { readFile, mkdir } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';
import { requestJson } from './network.mjs';
import { writeAtomic } from './files.mjs';

const format = 'selvedge-chatgpt-1';
const locks = new Map();

function claims(token) {
  try { return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8')); }
  catch { return {}; }
}
function text(value) { return typeof value === 'string' && value.trim().length > 0; }

export function validateCredential(value) {
  const fields = ['format', 'access_token', 'refresh_token', 'id_token', 'account_id', 'last_refresh'];
  if (!value || value.format !== format || Object.keys(value).length !== fields.length ||
      fields.some(key => !Object.hasOwn(value, key)) ||
      ['access_token', 'refresh_token', 'id_token', 'account_id'].some(key => !text(value[key])) ||
      !Number.isFinite(Date.parse(value.last_refresh))) throw new Error('Invalid current-format ChatGPT credential; sign in again');
  return value;
}

function credential(tokens, previous) {
  const access = tokens?.access_token;
  const id = tokens?.id_token ?? previous?.id_token;
  const account = claims(id ?? '')['https://api.openai.com/auth']?.chatgpt_account_id ??
    claims(access ?? '')['https://api.openai.com/auth']?.chatgpt_account_id ?? previous?.account_id;
  const result = validateCredential({ format, access_token: access, refresh_token: tokens?.refresh_token ?? previous?.refresh_token,
    id_token: id, account_id: account, last_refresh: new Date().toISOString() });
  if (previous && result.account_id !== previous.account_id) throw new Error('Token refresh changed the ChatGPT account');
  return result;
}

async function locked(filename, action) {
  const prior = locks.get(filename) ?? Promise.resolve();
  const pending = prior.catch(() => {}).then(async () => {
    await mkdir(path.dirname(filename), { recursive: true, mode: 0o700 });
    const lock = new DatabaseSync(`${filename}.lock`, { timeout: 1000 });
    try {
      lock.exec('CREATE TABLE IF NOT EXISTS owner (id INTEGER PRIMARY KEY); BEGIN EXCLUSIVE');
      return await action();
    } finally {
      try { lock.exec('ROLLBACK'); } catch {}
      lock.close();
    }
  });
  locks.set(filename, pending);
  try { return await pending; }
  finally { if (locks.get(filename) === pending) locks.delete(filename); }
}

export async function resolveAuth(profile, home, { signal, rejectedToken } = {}) {
  const filename = path.resolve(home, profile.auth_file);
  return locked(filename, async () => {
    const current = validateCredential(JSON.parse(await readFile(filename, 'utf8')));
    const expiration = claims(current.access_token).exp;
    const stale = typeof expiration === 'number' ? expiration * 1000 <= Date.now() + 300_000
      : Date.parse(current.last_refresh) <= Date.now() - 55 * 60_000;
    if (!stale && (rejectedToken === undefined || rejectedToken !== current.access_token)) return current;
    const response = await requestJson(`${profile.issuer}/oauth/token`, { signal,
      body: { client_id: profile.client_id, grant_type: 'refresh_token', refresh_token: current.refresh_token } });
    if (!response.ok) throw new Error(`ChatGPT token refresh failed with HTTP ${response.status}`);
    const next = credential(response.value, current);
    await writeAtomic(filename, next);
    return next;
  });
}

/** Only called by the explicit login command; it never runs during server startup. */
export async function login(profile, home, { signal, onCode = () => {} } = {}) {
  const lifetime = signal ? AbortSignal.any([signal, AbortSignal.timeout(15 * 60_000)]) : AbortSignal.timeout(15 * 60_000);
  const started = await requestJson(`${profile.issuer}/api/accounts/deviceauth/usercode`, {
    signal: lifetime, body: { client_id: profile.client_id },
  });
  if (!started.ok) throw new Error(`Device login could not start: HTTP ${started.status}`);
  const challenge = started.value;
  const interval = Number(challenge?.interval ?? 5);
  if (!text(challenge?.device_auth_id) || !text(challenge?.user_code) || !Number.isFinite(interval) || interval < 1 || interval > 60) {
    throw new Error('The login service returned an invalid device challenge');
  }
  await onCode({ url: `${profile.issuer}/codex/device`, code: challenge.user_code });
  for (;;) {
    lifetime.throwIfAborted();
    const response = await requestJson(`${profile.issuer}/api/accounts/deviceauth/token`, {
      signal: lifetime, body: { device_auth_id: challenge.device_auth_id, user_code: challenge.user_code },
    });
    if ([403, 404].includes(response.status)) { await delay(interval * 1000, undefined, { signal: lifetime }); continue; }
    if (!response.ok) throw new Error(`Device login failed: HTTP ${response.status}`);
    if (!text(response.value?.authorization_code) || !text(response.value?.code_verifier)) throw new Error('The login service returned an invalid authorization grant');
    const exchanged = await requestJson(`${profile.issuer}/oauth/token`, { signal: lifetime, body: {
      grant_type: 'authorization_code', client_id: profile.client_id, code: response.value.authorization_code,
      code_verifier: response.value.code_verifier, redirect_uri: `${profile.issuer}/deviceauth/callback`,
    } });
    if (!exchanged.ok) throw new Error(`Token exchange failed: HTTP ${exchanged.status}`);
    const saved = credential(exchanged.value);
    const filename = path.resolve(home, profile.auth_file);
    await locked(filename, () => writeAtomic(filename, saved));
    return { account_id: saved.account_id, filename };
  }
}
