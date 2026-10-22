import * as smd from './vendor/streaming-markdown.mjs';

export function createMarkdownFenceParser(onChange) {
  const stack = [];
  const fences = [];
  let ordinal = 0n;
  let prefix = '';
  const report = () => onChange(fences.map(({ type, ...fence }) => ({ ...fence })), prefix);
  const sink = {
    data: null,
    add_token: (_, type) => {
      if (type === smd.DOCUMENT) return;
      let fence = null;
      if (type === smd.CODE_BLOCK || type === smd.CODE_FENCE) {
        fence = { type, ordinal: ordinal++, kind: type === smd.CODE_FENCE ? 'fenced' : 'indented',
          info: '', code: '', closed: false };
        fences.push(fence);
      }
      stack.push({ type, fence });
    },
    end_token: () => {
      const entry = stack.pop();
      if (entry.fence) entry.fence.closed = true;
    },
    add_text: (_, value) => {
      const fence = stack.at(-1)?.fence;
      if (fence) fence.code += value;
    },
    set_attr: (_, attr, value) => {
      if (attr === smd.LANG && stack.at(-1)?.fence) stack.at(-1).fence.info = value;
    },
  };
  const parser = smd.parser(sink);
  return {
    write(chunk) {
      prefix += chunk;
      smd.parser_write(parser, chunk);
      report();
    },
    finish() {
      smd.parser_end(parser);
      report();
    },
  };
}

export function observeMarkdownFences(text) {
  let fences = [];
  const parser = createMarkdownFenceParser(observed => { fences = observed; });
  parser.write(text);
  parser.finish();
  return fences.map(fence => ({
    raw_info: fence.info,
    fence_kind: fence.kind,
    info_complete: true,
  }));
}

export function observeTextItems(items) {
  return Array.isArray(items) ? items.map(item => item?.type === 'text' && typeof item.text === 'string'
    ? observeMarkdownFences(item.text) : []) : [];
}
