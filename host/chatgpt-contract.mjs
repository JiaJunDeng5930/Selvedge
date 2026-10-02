export const chatgptToolNamespace = 'selvedge';

export function modelsURL(endpoint) {
  const url = new URL(endpoint);
  if (!/\/responses\/?$/.test(url.pathname)) throw new Error('ChatGPT endpoint must end in /responses');
  url.pathname = url.pathname.replace(/\/responses\/?$/, '/models');
  return url.href;
}
