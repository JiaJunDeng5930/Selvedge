import { constants } from 'node:fs';
import { access, appendFile, mkdir, mkdtemp, open } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { groups, viewports } from './catalog.mjs';
import { gallery } from './report.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const { values: options } = parseArgs({ options: {
  groups: { type: 'string' },
  viewports: { type: 'string' },
  out: { type: 'string' },
  help: { type: 'boolean', short: 'h' },
} });

if (options.help) {
  console.log(`Usage: bun run screenshots [--groups IDS] [--viewports IDS] [--out DIRECTORY]

Groups     ${Object.keys(groups).join(', ')}
Viewports  ${viewports.map(({ id }) => id).join(', ')}

Lists are comma-separated. The default captures all groups and sizes.
Each run writes a gallery, original images, and logs under a new directory
in .workpad/browser-screenshots or the specified output directory.
Set SELVEDGE_CHROMIUM_EXECUTABLE_PATH to use a particular Chrome or Chromium.`);
  process.exit(0);
}

function selection(value, known, option) {
  if (value === undefined) return known;
  const ids = value.split(',').map(id => id.trim());
  if (new Set(ids).size !== ids.length || ids.some(id => !known.includes(id))) {
    throw new Error(`Unknown or repeated ID in --${option} ${value}`);
  }
  return ids;
}

async function browserExecutable() {
  const override = process.env.SELVEDGE_CHROMIUM_EXECUTABLE_PATH;
  if (override) {
    const executable = resolve(override);
    await access(executable, constants.X_OK);
    return executable;
  }
  const onPath = ['chromium', 'chromium-browser', 'google-chrome', 'google-chrome-stable']
    .map(command => Bun.which(command)).find(Boolean);
  if (onPath) return onPath;
  if (process.platform === 'darwin') {
    const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
    if (await Bun.file(chrome).exists()) {
      await access(chrome, constants.X_OK);
      return chrome;
    }
  }
  throw new Error('Install Chrome or Chromium, or set SELVEDGE_CHROMIUM_EXECUTABLE_PATH.');
}

const groupIds = selection(options.groups, Object.keys(groups), 'groups');
const viewportIds = selection(options.viewports, viewports.map(({ id }) => id), 'viewports');
const sizes = viewportIds.map(id => viewports.find(viewport => viewport.id === id));
const executable = await browserExecutable();
const output = options.out ? resolve(options.out) : join(root, '.workpad/browser-screenshots');
await mkdir(output, { recursive: true });
const runDirectory = await mkdtemp(join(output, 'run-'));
console.log(`Writing screenshots to ${runDirectory}`);

async function captureGroup(id) {
  const { script, title, states } = groups[id];
  const directory = join(runDirectory, id);
  const log = `${id}/capture.log`;
  await mkdir(directory);
  const handle = await open(join(runDirectory, log), 'w');
  let exitCode;
  try {
    const child = Bun.spawn([process.execPath, fileURLToPath(new URL(script, import.meta.url))], {
      cwd: root,
      env: {
        ...process.env,
        SELVEDGE_CHROMIUM_EXECUTABLE_PATH: executable,
        SELVEDGE_SCREENSHOT_GROUP: id,
        SELVEDGE_SCREENSHOT_DIRECTORY: directory,
        SELVEDGE_SCREENSHOT_VIEWPORTS: viewportIds.join(','),
      },
      stdout: handle.fd,
      stderr: handle.fd,
    });
    exitCode = await child.exited;
  } finally {
    await handle.close();
  }

  const recordsFile = Bun.file(join(directory, 'captures.ndjson'));
  const lines = await recordsFile.exists()
    ? (await recordsFile.text()).trim().split('\n').filter(Boolean)
    : [];
  const pictures = new Map();
  const extras = [];
  for (const [index, line] of lines.entries()) {
    let record;
    try {
      record = JSON.parse(line);
    } catch (error) {
      // DEFENSE: An interrupted or failed write can leave an incomplete
      // capture record. Preserve the rest of the run and report the error.
      await appendFile(join(runDirectory, log), `\nInvalid capture record on line ${index + 1}: ${error.message}\n`);
      if (exitCode === 0) exitCode = 1;
      continue;
    }
    const item = record.file ? { ...record, file: `${id}/${record.file}` } : record;
    if (record.status === 'extra') extras.push(item);
    else pictures.set(`${item.state}/${item.viewport}/${item.variant}`, item);
  }
  const rows = states.map(state => ({
    state,
    cells: sizes.map(({ id: viewport }) => {
      const prefix = `${state}/${viewport}/`;
      const primary = pictures.get(prefix + 'top');
      return {
        viewport,
        status: primary?.status ?? 'missing',
        reason: primary?.reason,
        primary: primary?.file,
        bottom: pictures.get(prefix + 'bottom')?.file,
        right: pictures.get(prefix + 'right')?.file,
      };
    }),
  }));
  const missing = rows.flatMap(row => row.cells).filter(cell => cell.status === 'missing').length;
  console.log(`${id}: ${missing} missing; capture process exited ${exitCode}`);
  return { id, title, log, exitCode, rows, extras };
}

const sections = Array(groupIds.length);
let nextGroup = 0;
async function worker() {
  while (nextGroup < groupIds.length) {
    const index = nextGroup++;
    sections[index] = await captureGroup(groupIds[index]);
  }
}
// Each group starts a browser and an isolated service. Bound simultaneous runs.
await Promise.all([worker(), worker()]);

const counts = { captured: 0, missing: 0, 'not-applicable': 0 };
for (const { rows } of sections) {
  for (const { cells } of rows) {
    for (const { status } of cells) counts[status]++;
  }
}
const manifest = { viewports: sizes, sections, counts };
await Bun.write(join(runDirectory, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
const index = join(runDirectory, 'index.html');
await Bun.write(index, gallery(manifest));
console.log(`${counts.captured} captured, ${counts.missing} missing, ${counts['not-applicable']} not applicable\n${index}`);
if (counts.missing || sections.some(section => section.exitCode !== 0)) process.exitCode = 1;
