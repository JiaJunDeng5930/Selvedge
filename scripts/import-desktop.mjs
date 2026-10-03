import { createHash } from 'node:crypto';
import { open, readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const vendor = path.join(root, 'host/public/vendor');
const sha = value => createHash('sha256').update(value).digest('hex');
const names = ['desktop-tokens.css'];
const tokenHeader = version => `/* Codex Desktop ${version}: unchanged root/theme rules; no global element or Markdown rules. */\n@layer selvedge, properties, theme, base, components, utilities;\n`;

function demand(condition, message) { if (!condition) throw new Error(message); }
function digest(value, expected, label) {
  demand(/^[a-f0-9]{64}$/.test(expected ?? ''), `Invalid desktop source digest: ${label}`);
  demand(sha(value) === expected, `Desktop source mismatch: ${label}`);
}

export async function checkDesktop(directory = vendor) {
  const manifest = JSON.parse(await readFile(path.join(directory, 'desktop-source.json'), 'utf8'));
  demand(manifest.application?.name === 'openai-codex-electron' && /^\d+\.\d+\.\d+$/.test(manifest.application.version), 'Unexpected desktop application identity');
  demand(JSON.stringify(manifest.files?.map(file => file.file)) === JSON.stringify(names), 'Invalid desktop artifact inventory');
  for (const item of manifest.files) digest(await readFile(path.join(directory, item.file)), item.sha256, item.file);
  return 'Pinned Codex Desktop artifacts match their source manifest.';
}

async function readExactly(file, position, size) {
  demand(Number.isSafeInteger(position) && position >= 0 && Number.isSafeInteger(size) && size >= 0 && size <= 32 * 1024 * 1024, 'Invalid ASAR member bounds');
  const bytes = Buffer.alloc(size);
  let used = 0;
  while (used < size) {
    const { bytesRead } = await file.read(bytes, used, size - used, position + used);
    demand(bytesRead > 0, 'Truncated desktop archive');
    used += bytesRead;
  }
  return bytes;
}

async function sourceMembers(archive, manifest) {
  const file = await open(archive, 'r');
  try {
    const header = await readExactly(file, 0, 16);
    const base = 8 + header.readUInt32LE(4), length = header.readUInt32LE(12);
    demand(length < 16 * 1024 * 1024 && base >= 16 + length, 'Invalid ASAR header');
    const tree = JSON.parse((await readExactly(file, 16, length)).toString());
    const member = async name => {
      demand(/^\/(?:[A-Za-z0-9_.-]+\/)*[A-Za-z0-9_.-]+$/.test(name) && !name.split('/').includes('..'), 'Invalid ASAR member path');
      let node = tree;
      for (const part of name.slice(1).split('/')) node = node?.files?.[part];
      demand(node && !node.unpacked && !node.link && /^\d+$/.test(node.offset), `Missing packed desktop member: ${name}`);
      return readExactly(file, base + Number(node.offset), node.size);
    };
    const identity = JSON.parse((await member('/package.json')).toString());
    demand(identity.name === manifest.application.name && identity.version === manifest.application.version, 'The installed archive is not the pinned Codex Desktop version');
    const sources = {};
    for (const [key, input] of Object.entries(manifest.inputs)) {
      const bytes = await member(input.member);
      digest(bytes, input.sha256, input.member);
      sources[key] = bytes.toString('utf8');
    }
    return sources;
  } finally { await file.close(); }
}

function slice(sources, range, label, input = range.input) {
  const source = sources[input];
  demand(typeof source === 'string' && Number.isInteger(range.start) && Number.isInteger(range.end) && range.start >= 0 && range.end > range.start && range.end <= source.length, `Invalid desktop source range: ${label}`);
  const result = source.slice(range.start, range.end);
  digest(result, range.sha256, label);
  return result;
}

export async function reproduceDesktop({ archive, output }) {
  const manifest = JSON.parse(await readFile(path.join(vendor, 'desktop-source.json'), 'utf8'));
  const sources = await sourceMembers(archive, manifest);
  const tokens = tokenHeader(manifest.application.version) + manifest.css.tokenRules.map((range, index) =>
    range.parents.map(parent => `${parent}{`).join('') + slice(sources, range, `token rule ${index}`, 'css') + '}'.repeat(range.parents.length)).join('\n') + '\n';
  const results = { 'desktop-tokens.css': Buffer.from(tokens) };
  for (const item of manifest.files) digest(results[item.file], item.sha256, `reproduced ${item.file}`);
  await mkdir(output, { recursive: true });
  for (const [name, bytes] of Object.entries(results)) await writeFile(path.join(output, name), bytes);
  await writeFile(path.join(output, 'desktop-source.json'), JSON.stringify(manifest, null, 2) + '\n');
  return `${Object.keys(results).length} desktop artifacts reproduced byte-for-byte.`;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.length === 0 || (args.length === 1 && args[0] === '--check')) console.log(await checkDesktop());
  else {
    const options = {};
    while (args.length) {
      const name = args.shift(), value = args.shift();
      demand(['--asar', '--out'].includes(name) && value && !options[name], 'Use --asar PATH --out DIRECTORY');
      options[name] = value;
    }
    demand(options['--asar'] && options['--out'], 'Use --asar PATH --out DIRECTORY');
    console.log(await reproduceDesktop({ archive: path.resolve(options['--asar']), output: path.resolve(options['--out']) }));
  }
}
