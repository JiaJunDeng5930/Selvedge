import { randomBytes } from 'node:crypto';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { stringifyJson } from '../../host/codec.mjs';
import { defaultConfig, loadConfig, validateConfig } from '../../host/config.mjs';
import { startServer } from '../../host/server.mjs';
import { Service } from '../../host/service.mjs';
import { capture, launchBrowser, setViewport, viewports } from './capture.mjs';

const longProfileName = 'A long settings profile name '.repeat(12).trim();

async function startSettingsFixture(root) {
  const home = join(root, 'state');
  const fixtures = join(import.meta.dirname, '../../tests/fixtures');
  const tokenVariable = 'SELVEDGE_SCREENSHOT_CONNECTION_TOKEN';
  process.env[tokenVariable] = randomBytes(32).toString('base64url');
  const source = {
    ...defaultConfig,
    port: 0,
    chatgpt: false,
    profiles: { ...defaultConfig.profiles, [longProfileName]: { provider: 'echo', model: 'echo' } },
    mcp: { 'Workspace tools': { command: process.execPath,
      args: [join(fixtures, 'mcp-schema-contract.mjs'), 'mcp', join(root, 'mcp.log')] } },
    plugins: { sampleplugin: { command: process.execPath,
      args: [join(fixtures, 'natural-parameter-plugin.mjs'), join(root, 'plugin.log')] } },
    reasoning_evaluators: {
      'sample-evaluator': { provider: 'openrouter', model: 'sample-model', timeout_ms: 1800 },
    },
  };
  const seed = await Service.open({ home, cwd: root, config: validateConfig(source) });
  let project;
  try {
    const { reply } = await seed.command({
      op: 'create_project',
      name: 'Settings preview project',
      workspace: { roots: [root] },
    });
    if (!reply.ok) throw new Error(`Could not create the screenshot project: ${stringifyJson(reply)}`);
    project = reply.result.project_id;
  } finally {
    await seed.close();
  }

  // The local administration page reads the persisted configuration.
  await writeFile(join(home, 'config.json'), stringifyJson({
    ...source,
    chatgpt_plugin: {
      connections: {
        0: {
          token_env: tokenVariable,
          project_ids: [project],
          sandbox: { mode: 'workspace-write', network_access: false },
        },
      },
    },
  }));
  const { config } = await loadConfig({ home });
  return startServer({ home, cwd: root, config });
}

async function captureSettings(browser, url, viewport) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.setDefaultTimeout(10000);
  const errors = [];
  page.on('pageerror', error => errors.push(error));
  const settings = page.getByRole('dialog', { name: 'Settings', exact: true });
  const content = settings.locator('[data-semantic-key="settings-content"]');
  const editor = page.locator('dialog:is([data-semantic-key="settings-title-editor"], [data-semantic-key="settings-configuration-editor"])[open]');
  const editorBody = editor.locator('[data-surface-role="dialog-body"]');
  const button = (scope, name) => scope.getByRole('button', { name, exact: true });

  async function shot(name, scroller = editorBody) {
    const scrolls = await scroller.evaluate(node => {
      node.scrollTop = 0;
      return node.scrollHeight > node.clientHeight;
    });
    await capture(page, name, viewport);
    if (scrolls) {
      await scroller.evaluate(node => { node.scrollTop = node.scrollHeight; });
      await capture(page, name, viewport, 'bottom');
    }
  }

  async function section(name) {
    const select = settings.getByRole('combobox', { name: 'Settings section', exact: true });
    if (await select.isVisible()) await select.selectOption({ label: name });
    else await settings.getByRole('radio', { name, exact: true }).click();
    await content.getByRole('heading', { name, exact: true }).waitFor({ state: 'attached' });
    await shot(name.toLowerCase(), content);
  }

  async function edit(name, entry, variants) {
    await button(content, entry).click();
    await editor.waitFor();
    await shot(name);
    await variants?.();
    await editor.getByRole('button', { name: /^(Cancel|Discard changes)$/ }).click();
    await editor.waitFor({ state: 'hidden' });
  }

  async function disclosure(label, expanded) {
    const toggle = button(editor, label);
    if ((await toggle.getAttribute('aria-expanded') === 'true') !== expanded) await toggle.click();
  }

  try {
    await page.goto(url);
    const navigation = page.getByRole('navigation', { name: 'Global navigation', exact: true });
    await button(navigation, 'Settings').click();
    await settings.waitFor();
    await setViewport(page, viewport);

    await section('General');
    await edit('instructions', 'Edit instructions', async () => {
      await editor.getByRole('textbox', { name: 'Instructions', exact: true }).fill('Keep headings concise.\n保留中文。');
      await shot('instructions-dirty');
    });
    await edit('title-prompts', 'Edit title prompts');

    await section('Models');
    await edit('profile-new', 'Add profile', async () => {
      for (const [provider, state] of [['Responses API', 'responses'], ['ChatGPT', 'account'], ['ChatGPT Web', 'web']]) {
        await editor.getByRole('radio', { name: provider, exact: true }).click();
        await disclosure('Connection overrides', false);
        await shot(`profile-new-${state}`);
        await disclosure('Connection overrides', true);
        await shot(`profile-new-${state}-details`);
      }
    });
    for (const [name, state] of [['demo', 'profile-saved'], [longProfileName, 'profile-long']]) {
      await edit(state, `Edit ${name}`, async () => {
        await button(editor, 'Remove profile').click();
        await shot(`${state}-remove`);
      });
    }
    await edit('model-access', 'Configure access', async () => {
      const allow = editor.getByRole('switch', { name: 'Allow account models', exact: true });
      await allow.click();
      await shot('model-access-enabled');
      await disclosure('Connection overrides', true);
      await shot('model-access-details');
    });
    await edit('evaluator-new', 'Add evaluator', async () => {
      await disclosure('Connection and retries', true);
      await shot('evaluator-new-details');
    });
    await edit('evaluator-saved', 'Edit sample-evaluator');

    await section('Connectors');
    await edit('server-new', 'Add server', async () => {
      await button(editor, 'Add argument').click();
      await disclosure('Execution options', true);
      await shot('server-new-details');
    });
    await edit('server-saved', 'Edit Workspace tools');
    await edit('connection-new', 'Add connection', async () => {
      await button(editor, 'Add project ID').click();
      await shot('connection-new-list');
    });
    await edit('connection-saved', 'Edit 0');

    await section('Extensions');
    await edit('plugin-new', 'Add plugin', async () => {
      await button(editor, 'Add argument').click();
      await disclosure('Execution options', true);
      await shot('plugin-new-details');
    });
    await edit('plugin-saved', 'Edit sampleplugin');
    await edit('sources', 'Edit sources', async () => {
      await button(editor, 'Add path').click();
      await shot('sources-list');
    });

    await section('Tasks');
    await edit('cloud', 'Configure cloud', async () => {
      await button(editor, 'Add security group ID').click();
      await shot('cloud-list');
      await disclosure('Connection options', true);
      await shot('cloud-details');
    });

    await section('Context');
    await edit('limits', 'Edit limits', async () => {
      await button(editor, 'Add target').click();
      await shot('limits-record');
    });

    await section('Service');
    await edit('relay', 'Configure relay', async () => {
      await editor.getByRole('textbox', { name: 'Relay URL', exact: true }).fill('http://invalid.example.test');
      await button(editor, 'Save').click();
      await editor.locator('[data-semantic-key="save-error"]').waitFor();
      await shot('relay-error');
    });
    if (errors.length) throw new AggregateError(errors, 'Settings screenshot page errors');
  } finally {
    await page.close();
  }
}

const root = await mkdtemp(join(tmpdir(), 'selvedge-settings-screenshots-'));
try {
  const fixture = await startSettingsFixture(root);
  try {
    const browser = await launchBrowser();
    try {
      const failures = [];
      for (let index = 0; index < viewports.length; index += 3) {
        const batch = viewports.slice(index, index + 3);
        const results = await Promise.allSettled(batch.map(viewport => captureSettings(browser, fixture.url, viewport)));
        failures.push(...results.flatMap((result, position) => result.status === 'rejected'
          ? [new Error(`Settings screenshots failed for ${batch[position].id}`, { cause: result.reason })]
          : []));
      }
      if (failures.length) throw new AggregateError(failures, 'Could not capture all Settings screenshots');
    } finally {
      await browser.close();
    }
  } finally {
    await fixture.close();
  }
} finally {
  await rm(root, { recursive: true, force: true });
}
