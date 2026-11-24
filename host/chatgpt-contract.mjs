import { boundary } from './public/model-boundary.mjs';

// Codex requests the catalog with its semantic version, without the prerelease suffix.
const codexClientVersion = '0.171.0';

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
