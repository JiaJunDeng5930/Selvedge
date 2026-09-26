import { createHash } from 'node:crypto';
import path from 'node:path';

// Wire baseline, not a claim that this application is the Codex CLI.
// See docs/adr/0017-chatgpt-account-contract.md for pinned upstream sources.
export const codexContractVersion = '0.157.1';
export const defaultChatGPTAccount = Object.freeze({
  provider: 'chatgpt', endpoint: 'https://chatgpt.com/backend-api/codex/responses',
  auth_file: 'auth/chatgpt.json', issuer: 'https://auth.openai.com',
  client_id: 'app_EMoamEEZ73f0CkXaXp7hrann', timeout_ms: 300_000,
});

/** Stable per-home/task identity; no workspace path is sent in an HTTP header. */
export function chatgptSession(home, task) {
  const hash = createHash('sha256').update(`${path.resolve(home)}\0${task}`).digest('hex');
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-5${hash.slice(13, 16)}-a${hash.slice(17, 20)}-${hash.slice(20, 32)}`;
}

export function chatgptHeaders(credential, session) {
  return {
    authorization: `Bearer ${credential.access_token}`,
    'chatgpt-account-id': credential.account_id,
    originator: 'selvedge',
    'user-agent': `selvedge (codex-contract/${codexContractVersion})`,
    ...(session ? { session_id: session } : {}),
  };
}

export function modelsURL(endpoint) {
  const url = new URL(endpoint);
  if (!/\/responses\/?$/.test(url.pathname)) throw new Error('ChatGPT endpoint must end in /responses');
  url.pathname = url.pathname.replace(/\/responses\/?$/, '/models');
  url.searchParams.set('client_version', codexContractVersion);
  return url.href;
}
