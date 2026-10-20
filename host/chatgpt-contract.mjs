import { boundary } from './public/model-boundary.mjs';

export const chatgptToolNamespace = boundary('account.contract', {}).namespace;

export function modelsURL(endpoint) {
  const url = new URL(endpoint);
  const observation = Object.fromEntries(['href', 'protocol', 'origin', 'hostname', 'pathname', 'search', 'username', 'password', 'hash'].map(key => [key, url[key]]));
  url.pathname = boundary('account.models_url', { endpoint, url: observation });
  return url.href;
}
