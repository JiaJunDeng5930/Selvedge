import { boundary } from './public/model-boundary.mjs';

export function modelsURL(endpoint) {
  const url = new URL(endpoint);
  url.pathname = boundary('account.models_url', { url: { pathname: url.pathname } });
  return url.href;
}
