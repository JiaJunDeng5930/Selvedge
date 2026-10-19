import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { decodeJwt } from 'jose';
import { StdioRpc } from './stdio-rpc.mjs';
import { boundary } from './public/model-boundary.mjs';

function loginTarget(url) {
  const parsed = new URL(url);
  return boundary('codex_audio_account.login_target', { url,
    protocol: parsed.protocol, hostname: parsed.hostname, pathname: parsed.pathname,
    username: parsed.username, password: parsed.password, port: parsed.port });
}

/** The official Codex process owns this application's login and rotating credentials. */
export function createCodexAudioAccount({ home, onChange = () => {}, command } = {}) {
  const plan = boundary('codex_audio_account.plan', { command: command ?? process.env.SELVEDGE_CODEX_BIN ?? 'codex' });
  let rpc, starting, closed = false;

  async function start() {
    if (closed) throw new Error('ChatGPT audio account is closed');
    await mkdir(path.join(home, plan.home_name), { recursive: true, mode: 0o700 });
    // The child owns a separate credential store. Inherited API keys, external
    // auth tokens and login-client overrides must not select another auth route.
    const env = Object.fromEntries(['OPENAI_API_KEY', 'OPENAI_ACCESS_TOKEN', 'CODEX_API_KEY',
      'CODEX_ACCESS_TOKEN', 'CHATGPT_ACCESS_TOKEN', 'CODEX_APP_SERVER_LOGIN_CLIENT_ID'].map(name => [name, undefined]));
    env.CODEX_HOME = path.join(home, plan.home_name);
    rpc = new StdioRpc('codex-audio', { command: plan.command, args: plan.args, env, cwd: env.CODEX_HOME }, plan,
      { label: 'Official Codex audio account', timeoutMs: plan.timeout_ms,
        decodeMessage: message => {
          // Bearer bytes stay outside the native JSON transport calculation.
          // The public getAuthStatus result has one opaque authToken field.
          const observed = message?.result && Object.hasOwn(message.result, 'authToken')
            ? { ...message, result: { ...message.result, authToken: null } } : message;
          return boundary('codex_audio_account.rpc_message', { message: observed });
        },
        decodeResult: (value, message) => message?.result && Object.hasOwn(message.result, 'authToken')
          ? { ...value, authToken: message.result.authToken } : value });
    rpc.on('notification', message => {
      if (boundary('codex_audio_account.notification', message)) onChange({ type: 'account_changed' });
    });
    try {
      await rpc.request(plan.initialize.method, plan.initialize.params);
      rpc.notify(plan.initialized.method, plan.initialized.params);
      return rpc;
    } catch (error) {
      await rpc.close();
      // DEFENSE: The default executable can be absent on a machine that only installed Selvedge.
      if (error.code === 'ENOENT') throw new Error('Install the official Codex CLI or configure SELVEDGE_CODEX_BIN for ChatGPT voice sign-in', { cause: error });
      throw error;
    }
  }

  function component() {
    if (closed) return Promise.reject(new Error('ChatGPT audio account is closed'));
    return starting ??= start();
  }

  async function request(name, options) {
    options?.signal?.throwIfAborted();
    const client = await component();
    return client.request(plan[name].method, plan[name].params, options);
  }

  async function authorization({ signal, refresh = false, expectedAccountId = null } = {}) {
    const account = (await request('account', { signal })).account;
    boundary('codex_audio_account.account', { account });
    let status;
    try { status = await request(refresh ? 'refresh' : 'authorize', { signal }); }
    catch (error) {
      signal?.throwIfAborted();
      // DEFENSE: getAuthStatus is a deprecated public token-export RPC and can be removed by an installed Codex version.
      throw new Error(`Official Codex does not provide the required audio token RPC: ${error.message}`, { cause: error });
    }
    const token = status.authToken;
    const tokenPresent = typeof token === 'string' && token.length > 0;
    let accountId = null;
    if (tokenPresent) {
      // The bearer comes from the trusted official process, which authenticated
      // it. Decode only its routing claim; this is not a JWT authentication check.
      try { accountId = decodeJwt(token)['https://api.openai.com/auth']?.chatgpt_account_id ?? null; }
      // DEFENSE: An opaque or malformed token cannot supply the account binding required by the audio backend.
      catch { accountId = null; }
    }
    const admitted = boundary('codex_audio_account.authorization', { account,
      auth_method: status.authMethod, token_present: tokenPresent,
      account_id: accountId, expected_account_id: expectedAccountId });
    return { headers: Object.freeze({ authorization: `Bearer ${token}`, originator: plan.initialize.params.clientInfo.name }), account_id: admitted.account_id,
      refreshAfterRejection: ({ signal: retrySignal } = {}) => authorization({ signal: retrySignal,
        refresh: true, expectedAccountId: admitted.account_id }) };
  }

  return {
    async connections(options = {}) {
      const result = await request('account', options);
      return boundary('codex_audio_account.connections', result);
    },
    async authorize(connection, options = {}) {
      boundary('codex_audio_account.connection', { connection });
      return authorization(options);
    },
    async startLogin(options = {}) {
      const result = await request('login', options);
      const target = loginTarget(result.authUrl);
      return boundary('codex_audio_account.login_result', { ...target, login_id: result.loginId });
    },
    async close() {
      closed = true;
      // A directory creation may still be pending when Service shutdown starts.
      // Wait for initialization before releasing the only owned child process.
      if (starting) {
        try { await starting; }
        // DEFENSE: Failed initialization already closed its child and is reported to its original caller.
        catch { return; }
      }
      await rpc?.close();
    },
  };
}
