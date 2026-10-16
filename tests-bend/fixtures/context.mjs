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
  semantics: 'Instructions from the selected workspace AGENTS.md.', scope: 'workspace',
  observer: { type: 'workspace_file', relative: 'AGENTS.md' },
  identity: [{ name: 'workspace', source: { type: 'workspace_root' }, required: true }],
  fields: content,
};

function introduction(definition, identity, revision, text) {
  return { role: 'task_context', type: 'context_change', change: { type: 'introduce', snapshot: {
    key: { type: definition.kind, definition, identity }, revision,
    value: { type: definition.kind, fields: { content: text } },
  } } };
}

export const configuredContext = text => introduction(configuredInstruction, { origin: 'configured' }, 'initial', text);
export const projectContext = (workspace, revision, text) => introduction(projectGuidance, { workspace }, revision, text);
