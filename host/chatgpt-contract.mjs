import { createHash } from 'node:crypto';

export const chatgptOAuthResource = 'https://api.openai.com/v1';
export const chatgptScopes = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';
export const chatgptToolNamespace = 'selvedge';
export const defaultChatGPTAccount = Object.freeze({
  provider: 'chatgpt', endpoint: 'https://api.openai.com/v1/responses',
  auth_file: 'auth/chatgpt.json', issuer: 'https://auth.openai.com', timeout_ms: 300_000,
});

export function chatgptAccountIdentity(issuer, clientId, subject) {
  return createHash('sha256').update(`${issuer}\0${clientId}\0${subject}`).digest('hex');
}

export function chatgptHeaders(credential) {
  return { authorization: `Bearer ${credential.access_token}` };
}

export function modelsURL(endpoint) {
  const url = new URL(endpoint);
  if (!/\/responses\/?$/.test(url.pathname)) throw new Error('ChatGPT endpoint must end in /responses');
  url.pathname = url.pathname.replace(/\/responses\/?$/, '/models');
  return url.href;
}
