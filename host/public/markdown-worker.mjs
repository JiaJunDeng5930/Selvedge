let highlighter;
let math;
self.onmessage = async ({ data }) => {
  const { id, kind, text, language } = data;
  let markup;
  if (kind === 'code') {
    highlighter ??= import('./vendor/highlight.mjs').then(module => module.default);
    const hl = await highlighter;
    // DEFENSE: Markdown authors may omit a language or name one absent from the pinned highlighter; preserve plain text.
    if (!language || !hl.getLanguage(language)) return self.postMessage({ id });
    markup = hl.highlight(text, { language, ignoreIllegals: true }).value;
  } else if (kind === 'math') {
    math ??= import('./vendor/katex.mjs');
    const katex = await math;
    // DEFENSE: Model-authored TeX may be invalid or recursively expanding; render diagnostics under the existing expansion/size bounds.
    markup = katex.renderToString(text, { output: 'mathml', displayMode: language === 'display', trust: false,
      throwOnError: false, strict: 'ignore', maxExpand: 200, maxSize: 10 });
  }
  self.postMessage({ id, markup });
};
