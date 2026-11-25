import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

export const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const buildDirectory = path.join(root, '.build');
export const targets = {
  schema: { module: 'Adapters.ModelSchema', model: 'SchemaModel', entry: ['call'], global: '__selvedgeSchema', exported: 'call' },
  kernel: { module: 'Kernel.Packet', model: 'KernelModel', entry: ['initial', 'journal_packet', 'world_json',
    'task_registry_restore', 'task_registry_contents', 'task_registry_lookup', 'task_registry_changes', 'named_titles',
    'shared_publication', 'task_publication', 'task_history_since', 'history_publication', 'task_publication_references',
    'board_task_dependencies', 'workflow_task_dependencies', 'compaction_task_dependencies',
    'publication_project', 'assess', 'remote_reconciliation_needed'],
  global: '__selvedgeKernel' },
  host: { module: 'Adapters.Api', model: 'HostModel', entry: ['call'], global: '__selvedgeHost', exported: 'call' },
  browser: { module: 'Browser.Runtime', model: 'BrowserModel', entry: ['call', 'native_document', 'materialize_native_roots'], global: '__selvedgeBrowser', exported: 'browserCall' },
  interaction: { module: 'Browser.Application', model: 'InteractionModel', entry: ['call', 'prepare', 'rebase', 'prepared_call', 'native_document', 'native_region', 'native_stream', 'materialize_native_roots'], global: '__selvedgeInteraction', exported: 'interactionCall' }
};
export const jsonEntries = {
  selvedge_parse_json: 'Foundation.TextJson.parse_json',
  selvedge_render_json: 'Foundation.TextJson.render_json',
  selvedge_parse_input_json: 'Foundation.TextJson.parse_input_json',
  selvedge_input_nesting: 'Foundation.TextJson.input_nesting',
  selvedge_input_nesting_error: 'Foundation.TextJson.input_nesting_error',
  selvedge_consume_input_nesting: 'Foundation.TextJson.consume_input_nesting'
};

export async function run(command, args) {
  const output = await new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: root, stdio: ['ignore', 'pipe', 'pipe'] });
    const chunks = [];
    child.stdout.on('data', chunk => chunks.push(chunk));
    child.stderr.on('data', chunk => chunks.push(chunk));
    child.on('error', reject);
    child.on('close', code => resolve({ code, text: Buffer.concat(chunks).toString() }));
  });
  if (output.code !== 0) {
    await mkdir(path.join(buildDirectory, 'logs'), { recursive: true });
    const filename = path.join(buildDirectory, 'logs', `${path.basename(command)}-${Date.now()}.log`);
    await writeFile(filename, output.text);
    throw new Error(`${command} failed (${output.code}); full output: ${filename}\n${output.text.slice(-5000)}`);
  }
  return output.text;
}
