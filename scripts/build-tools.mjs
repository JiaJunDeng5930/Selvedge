import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

export const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const buildDirectory = path.join(root, '.build');
export const targets = {
  schema: { module: 'Adapters.ModelSchema', model: 'SchemaModel', entry: ['call'], global: '__selvedgeSchema', exported: 'call' },
  kernel: { module: 'Kernel.Packet', model: 'KernelModel', entry: ['initial', 'journal_packet', 'world_json',
    'task_registry_restore', 'project_registry_restore', 'card_registry_restore', 'workflow_registry_restore',
    'restore_title_scope', 'task_registry_contents', 'task_registry_lookup', 'task_registry_changes', 'named_title_changes',
    'title_registry_restore', 'title_registry_changes',
    'shared_publication', 'task_publication', 'task_publication_busy', 'task_history_since', 'history_changes_bindings', 'history_publication', 'task_publication_references',
    'board_task_cards', 'board_unlinked_cards', 'board_active_owner', 'board_linked_profile',
    'task_workflow_instances', 'workflow_instance_at', 'workflow_instance_ticket',
    'card_publication_at', 'project_publication_at', 'compaction_task_dependencies',
    'publication_project', 'assess', 'remote_reconciliation_needed'],
  global: '__selvedgeKernel' },
  host: { module: 'Adapters.Api', model: 'HostModel', entry: ['call'], global: '__selvedgeHost', exported: 'call' },
  browser: { module: 'Browser.Runtime', model: 'BrowserModel', entry: ['call', 'native_document', 'materialize_native_roots'], global: '__selvedgeBrowser', exported: 'browserCall' },
  interaction: { module: 'Browser.Application', model: 'InteractionModel', entry: ['call', 'prepare', 'rebase', 'task_index_depth', 'prepared_call', 'native_document', 'native_region', 'native_stream', 'materialize_native_roots'], global: '__selvedgeInteraction', exported: 'interactionCall' }
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
