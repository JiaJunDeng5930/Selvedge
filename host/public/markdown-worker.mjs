let highlighter;
let math;
self.onmessage = async ({ data }) => {
  const { id, kind, text, language } = data;
  try {
    let markup;
    if (kind === 'code' && text.length <= 24000) {
      highlighter ??= import('./vendor/highlight.mjs').then(module => module.default);
      const hl = await highlighter;
      if (!language || !hl.getLanguage(language)) return self.postMessage({ id });
      markup = hl.highlight(text, { language, ignoreIllegals: true }).value;
    } else if (kind === 'math' && text.length <= 4000) {
      math ??= import('./vendor/katex.mjs');
      const katex = await math;
      markup = katex.renderToString(text, { output: 'mathml', displayMode: language === 'display', trust: false,
        throwOnError: false, strict: 'ignore', maxExpand: 200, maxSize: 10 });
    }
    self.postMessage({ id, markup });
  } catch { self.postMessage({ id }); }
};
