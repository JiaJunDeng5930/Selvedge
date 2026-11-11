import { boundary } from './public/model-boundary.mjs';

// Codex selects the model catalog by the released CLI's semantic version.
const codexClientVersion = '0.167.1';

export function modelsURL(endpoint) {
  const url = new URL(endpoint);
  url.pathname = boundary('account.models_url', { url: { pathname: url.pathname } });
  return url.href;
}

export function modelCatalogURL(endpoint) {
  const url = new URL(modelsURL(endpoint));
  url.searchParams.set('client_version', codexClientVersion);
  return url.href;
}
