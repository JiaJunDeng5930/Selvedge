const content = [{ name: 'content', source: { type: 'body' }, required: false }];
const configuredInstruction = {
  kind: 'configured_instruction',
  semantics: 'Instructions configured for this task.', scope: 'global',
  observer: { type: 'config_text', setting: 'instructions' },
  identity: [{ name: 'origin', source: { type: 'constant', value: 'configured' }, required: true }],
  fields: content,
};
const projectGuidance = {
  kind: 'project_guidance',
  semantics: 'Apply these instructions within applies_to. The precedence directory orders guidance by ancestry: descendant directories take priority over ancestors; AGENTS.override.md takes priority over AGENTS.md in the same directory. Scope does not change execution permissions.', scope: 'primary_workspace',
  observer: { type: 'primary_guidance', policy: {
    files: ['AGENTS.override.md', 'AGENTS.md'], directories: [], repository_markers: ['.git'],
    excluded: ['.git', '.hg', '.svn', 'node_modules', 'vendor', '.build', 'dist', 'build', 'target', '.next', '.cache', '.workpad', '__pycache__', '.venv', 'venv', '.agents', '.claude'],
    max_directories: 10000, max_entries: 100000, max_sources: 1024, max_bytes: 262144,
  } },
  identity: [{ name: 'workspace', source: { type: 'workspace_root' }, required: true }],
  fields: [...content, ...['path', 'applies_to', 'precedence'].map(name => ({ name, source: { type: 'observation_field', field: name }, required: true }))],
};

function introduction(definition, identity, revision, text, fields = {}) {
  return { role: 'task_context', type: 'context_change', change: { type: 'introduce', snapshot: {
    key: { type: definition.kind, definition, identity }, revision,
    value: { type: definition.kind, fields: { content: text, ...fields } },
  } } };
}

export const configuredContext = text => introduction(configuredInstruction, { origin: 'configured' }, 'initial', text);
export const projectContext = (workspace, revision, text) => introduction(projectGuidance, { workspace }, revision, text,
  { path: `${workspace === '/' ? '' : workspace}/AGENTS.md`, applies_to: workspace, precedence: workspace });
