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

const searchTextBlocks = new Set([
  smd.PARAGRAPH, smd.HEADING_1, smd.HEADING_2, smd.HEADING_3, smd.HEADING_4, smd.HEADING_5, smd.HEADING_6,
  smd.CODE_BLOCK, smd.CODE_FENCE, smd.BLOCKQUOTE, smd.LIST_ITEM, smd.TABLE_CELL, smd.EQUATION_BLOCK, smd.RULE,
]);

/** Observe text and fence metadata using the parser that renders the conversation. */
export function observeMarkdownSearchBlocks(text) {
  const blocks = [];
  const stack = [];
  let fragments = [];
  let fence;
  const flush = () => {
    if (fragments.length) blocks.push({ text: fragments.join(''), ...(fence && { fence }) });
    fragments = [];
  };
  const sink = {
    data: null,
    add_token: (_, type) => {
      if (type === smd.DOCUMENT) return;
      if (searchTextBlocks.has(type)) flush();
      if (type === smd.CODE_FENCE) fence = { raw_info: '', fence_kind: 'fenced', info_complete: true };
      if (type === smd.LINE_BREAK) fragments.push(' ');
      stack.push(type);
    },
    end_token: () => {
      const type = stack.pop();
      if (searchTextBlocks.has(type)) flush();
      if (type === smd.CODE_FENCE) fence = undefined;
    },
    add_text: (_, fragment) => fragments.push(fragment),
    set_attr: (_, attr, value) => {
      if (attr === smd.LANG && stack.at(-1) === smd.CODE_FENCE) fence.raw_info = value;
    },
  };
  const parser = smd.parser(sink);
  smd.parser_write(parser, text);
  smd.parser_end(parser);
  flush();
  return blocks;
}
