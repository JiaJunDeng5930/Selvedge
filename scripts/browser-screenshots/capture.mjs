import { appendFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { chromium } from 'playwright-core';
import { interactiveMarkdownFixture } from '../../tests/fixtures/interactive-markdown.mjs';
import { groups, viewports as allViewports } from './catalog.mjs';

export const group = process.env.SELVEDGE_SCREENSHOT_GROUP;
const directory = process.env.SELVEDGE_SCREENSHOT_DIRECTORY;
const selected = process.env.SELVEDGE_SCREENSHOT_VIEWPORTS?.split(',');
export const viewports = allViewports.filter(({ id }) => selected?.includes(id));

if (!Object.hasOwn(groups, group) || !directory || !viewports.length) {
  throw new Error('Start screenshot scenarios with bun run screenshots.');
}

const captures = new Set();

function cell(state, viewport, variant) {
  const size = viewports.find(({ id }) => id === (viewport.id ?? viewport));
  if (!size || !groups[group].states.includes(state) || !['top', 'bottom', 'right'].includes(variant)) {
    throw new Error(`Unknown screenshot cell: ${group}/${viewport.id ?? viewport}/${state}/${variant}`);
  }
  return { state, viewport: size.id, variant };
}

function reserve(key) {
  if (captures.has(key)) throw new Error(`Duplicate screenshot result: ${key}`);
  captures.add(key);
}

function record(entry) {
  return appendFile(join(directory, 'captures.ndjson'), JSON.stringify(entry) + '\n');
}

async function paint(page) {
  await page.evaluate(async () => {
    await document.fonts.ready;
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  });
}

export async function setViewport(page, { width, height, textScale }) {
  await page.setViewportSize({ width, height });
  await page.evaluate(scale => {
    document.documentElement.style.setProperty('font-size', `${scale}%`, 'important');
  }, textScale);
  await paint(page);
}

async function screenshot(page, folder, name, size) {
  await paint(page);
  const image = await page.screenshot({ animations: 'disabled', scale: 'css' });
  const width = image.readUInt32BE(16);
  const height = image.readUInt32BE(20);
  if (width !== size.width || height !== size.height) {
    throw new Error(`${name} captured at ${width}×${height} instead of ${size.width}×${size.height}`);
  }
  const file = `${folder}/${name}.png`;
  await mkdir(join(directory, folder), { recursive: true });
  await Bun.write(join(directory, file), image);
  return { file, width, height };
}

export async function capture(page, state, viewport, variant = 'top') {
  const entry = cell(state, viewport, variant);
  reserve(`${entry.viewport}/${state}/${variant}`);
  const name = variant === 'top' ? state : `${state}--${variant}`;
  const size = viewports.find(({ id }) => id === entry.viewport);
  const image = await screenshot(page, entry.viewport, name, size);
  await record({ ...entry, ...image, status: 'captured' });
}

export async function captureExtra(page, name) {
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(name)) throw new Error(`Invalid extra screenshot name: ${name}`);
  reserve(`extras/${name}`);
  const image = await screenshot(page, 'extras', name, page.viewportSize());
  await record({ name, ...image, status: 'extra' });
}

export async function notApplicable(state, viewport, reason) {
  const entry = cell(state, viewport, 'top');
  reserve(`${entry.viewport}/${state}/top`);
  await record({ ...entry, status: 'not-applicable', reason });
}

export function launchBrowser() {
  return chromium.launch({ executablePath: process.env.SELVEDGE_CHROMIUM_EXECUTABLE_PATH, headless: true });
}

export async function withBrowserFixture(run) {
  const fixture = await interactiveMarkdownFixture();
  try {
    const browser = await launchBrowser();
    try {
      const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
      page.setDefaultTimeout(10000);
      const errors = [];
      page.on('pageerror', error => errors.push(error));
      await page.goto(fixture.running.url);
      await page.getByRole('navigation', { name: 'Global navigation', exact: true }).waitFor();
      const command = async input => {
        const { reply } = await fixture.command(input);
        if (!reply.ok) throw new Error(`Could not seed screenshot fixture: ${JSON.stringify(reply)}`);
        return reply.result;
      };
      const result = await run({ ...fixture, browser, page, command });
      if (errors.length) throw new AggregateError(errors, 'Browser fixture page errors');
      return result;
    } finally {
      await browser.close();
    }
  } finally {
    await fixture.close();
  }
}
