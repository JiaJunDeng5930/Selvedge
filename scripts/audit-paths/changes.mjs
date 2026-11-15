import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { root, run } from '../build-tools.mjs';

const gallinaPaths = [':(glob)theories/**/*.v', ':(glob)requirements/**/*.v'];
const diff = ['diff', '--no-ext-diff', '--no-textconv', '--no-renames'];

export async function changedGallina(base) {
  const commit = (await run('git', ['rev-parse', '--verify', '--end-of-options', `${base}^{commit}`])).trim();
  const [tracked, untracked] = await Promise.all([
    run('git', [...diff, '--name-only', '-z', '--diff-filter=AMT', commit, '--', ...gallinaPaths]),
    run('git', ['ls-files', '-z', '--others', '--exclude-standard', '--', ...gallinaPaths]),
  ]);
  const changes = new Map();
  for (const file of untracked.split('\0').filter(Boolean)) changes.set(file, [{ start: 1, count: Infinity }]);
  for (const file of tracked.split('\0').filter(Boolean)) {
    const patch = await run('git', [
      ...diff, '--no-color', '--unified=0', '--inter-hunk-context=0', commit, '--', `:(literal)${file}`,
    ]);
    const ranges = [...patch.matchAll(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/gm)]
      .map(([, start, count = '1']) => ({ start: Number(start), count: Number(count) }));
    if (ranges.length) changes.set(file, ranges);
  }
  return changes;
}

export function touches(ranges, { first, last }) {
  return ranges.some(({ start, count }) => count === 0
    ? first <= start && start < last
    : start <= last && start + count > first);
}

function sentences(source) {
  const spans = [];
  let start;
  let depth = 0;
  let quoted = false;
  // Count a period only at a sentence boundary, outside strings and nested Rocq comments.
  for (const { 0: token, groups, index } of source.matchAll(/\(\*|\*\)|"|(?<end>(?<!\.)\.(?=[ \t\r\n]|\(\*|$))|[^ \t\r\n]/g)) {
    if (!quoted && token === '(*') depth++;
    else if (depth && token === '*)') depth--;
    else if (!depth) {
      start ??= index;
      if (token === '"') quoted = !quoted;
      if (groups.end && !quoted) {
        spans.push({ start, end: index });
        start = undefined;
      }
    }
  }
  return spans;
}

export async function declarations(file) {
  const [bytes, glob] = await Promise.all([
    readFile(path.join(root, file)),
    readFile(path.join(root, file.slice(0, -2) + '.glob'), 'utf8'),
  ]);
  // Rocq's .glob locations count UTF-8 bytes.
  const source = bytes.toString('latin1');
  const spans = sentences(source);
  const lines = [0, ...Array.from(source.matchAll(/\n/g), match => match.index + 1)];
  const lineAt = offset => lines.findLastIndex(start => start <= offset) + 1;
  const result = new Map();
  let index = 0;
  const names = Array.from(glob.matchAll(/^\w+ (\d+):\d+ <> (\S+)$/gm),
    ([, offset, name]) => ({ offset: Number(offset), name })).sort((a, b) => a.offset - b.offset);
  for (const { name, offset } of names) {
    while (index < spans.length && spans[index].end < offset) index++;
    const span = spans[index];
    if (span && span.start <= offset) {
      result.set(name, { first: lineAt(span.start), last: lineAt(span.end), nameLine: lineAt(offset) });
    }
  }
  return result;
}
