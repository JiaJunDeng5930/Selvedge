import { createHash } from 'node:crypto';
import { realpath } from 'node:fs/promises';
import { isDeepStrictEqual } from 'node:util';
import path from 'node:path';
import { configurationFilename, contextConfiguration, defaultConfig } from './config.mjs';
import { snapshotContextFile } from './project.mjs';
import { proposeContextPatch } from './context-patches.mjs';
import { boundary } from './public/model-boundary.mjs';
import { createContextDiscovery, isContextDiscovery, contextDescriptor } from './context-discovery.mjs';

const configFileLimit = 1024 * 1024;

function revision(value) {
  return createHash('sha256').update(JSON.stringify(value), 'utf8').digest('hex');
}

function fieldRecord(entries) {
  return Object.fromEntries(entries);
}

function identityValue(source, environment) {
  switch (source.type) {
    case 'constant': return source.value;
    case 'home_root': return environment.home;
    case 'source_path': return environment.filename;
    case 'workspace_root': return environment.workspace;
  }
}

function contextKey(definition, environment) {
  const identity = fieldRecord(definition.identity.map(field => [field.name,
    boundary('config.context_field', { definition, identity: true, field: field.name,
      value: identityValue(field.source, environment) })]));
  return { type: definition.kind, definition, identity };
}

function metadataFields(content) {
  const frontmatter = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(content);
  // DEFENSE: User-authored SKILL.md files must declare the metadata projected into model context.
  if (!frontmatter) throw new TypeError('Context metadata requires YAML frontmatter');
  let metadata;
  // DEFENSE: Invalid YAML in a skill file must fail observation instead of injecting guessed metadata.
  try { metadata = Bun.YAML.parse(frontmatter[1]); }
  catch { throw new TypeError('Context frontmatter is not valid YAML'); }
  // DEFENSE: Valid YAML can contain a scalar/list, while skill metadata requires a field record.
  if (metadata === null || typeof metadata !== 'object' || Array.isArray(metadata)) {
    throw new TypeError('Context frontmatter must contain a field record');
  }
  return metadata;
}

async function snapshotSource(definition, environment, key, limits, options) {
  const workspaceSource = contextDescriptor(definition.observer).workspace;
  const content = definition.observer.type === 'native_text' ? definition.observer.content
    : definition.observer.type === 'config_text' ? environment.config[definition.observer.setting]
    : (await snapshotContextFile(environment.filename, limits, { ...options,
      filesystem: workspaceSource ? options.workspaceEnvironment?.filesystem : undefined }))?.content;
  if (content === undefined) return null;
  const metadata = definition.fields.some(field => field.source.type === 'metadata') ? metadataFields(content) : undefined;
  const fields = fieldRecord(definition.fields.map(field => {
    let value;
    switch (field.source.type) {
      case 'body': value = content; break;
      case 'metadata': value = metadata[field.source.field]; break;
      case 'identity': value = key.identity[field.source.field]; break;
      case 'observation_field': value = environment.observations[field.source.field]; break;
    }
    return [field.name, boundary('config.context_field', { definition, identity: false, field: field.name, value })];
  }));
  const value = { type: definition.kind, fields };
  return { key, revision: definition.observer.type === 'native_text' ? definition.observer.revision : revision(value), value };
}

async function mutableConfiguration(config, definitions, limits, options) {
  const filename = configurationFilename(config);
  if (filename === undefined) return contextConfiguration(config, definitions);
  const file = await snapshotContextFile(filename, { ...limits, project_context_bytes: configFileLimit }, options);
  if (file === null) return contextConfiguration(defaultConfig, definitions);
  let value;
  // DEFENSE: A user may save malformed config.json while context settings are being refreshed.
  try { value = JSON.parse(file.content); }
  catch { throw new TypeError('Context configuration is not valid JSON'); }
  return contextConfiguration(value, definitions);
}

/** Observe the current metadata catalog independently of any task history. */
export async function observeSkillCatalog(workspace, { home, config, limits, signal, environment } = {}) {
  const definitions = boundary('config.context_definitions', {}).filter(definition => contextDescriptor(definition.observer).catalog);
  // NOTE: A first catalog has no accepted bindings on which the normal observer
  // can report a failed config_files refresh. Resolve it before observing files.
  const current = await mutableConfiguration(config, definitions, limits, { signal });
  const observations = await observeContextSources({ definitions, bindings: [], settings: { workspace } },
    { home, config: { ...config, ...current }, limits, signal, environment });
  const failed = observations.find(observation => observation.type === 'failure');
  // DEFENSE: Incomplete or unreadable skill discovery must remain a visible
  // catalog failure rather than publishing a partial list as a complete result.
  if (failed) throw new Error(failed.message);
  return observations.filter(observation => observation.type === 'present')
    .map(observation => observation.snapshot.value.fields);
}

/** Interpret native source descriptors; only the native history operation admits changes. */
export async function observeContextSources(effect, { home, config, limits, signal, onDiagnostic, environment: workspaceEnvironment } = {}) {
  const installation = await realpath(home);
  const definitions = effect.definitions;
  const bindings = effect.bindings;
  const options = { signal, workspaceEnvironment };
  const workspace = effect.settings.workspace.primary_root;
  const configuration = mutableConfiguration(config, definitions, limits, options);
  // DEFENSE: An unreadable configuration must preserve its previous bindings while
  // independent file observations can still proceed.
  const configurationResult = configuration.then(value => ({ value }), error => ({ error }));
  const discover = createContextDiscovery({ home: installation, settings: effect.settings, signal });
  const candidates = [...new Set(definitions.filter(definition => isContextDiscovery(definition.observer))
    .flatMap(definition => [...definition.observer.policy.files, ...definition.observer.policy.repository_markers,
      ...definition.observer.policy.directories]))];
  const maximumEntries = Math.max(0, ...definitions.filter(definition => isContextDiscovery(definition.observer))
    .map(definition => definition.observer.policy.max_entries));
  const discoverWorkspace = workspaceEnvironment
    ? createContextDiscovery({ home: installation, settings: effect.settings, signal, filesystem: workspaceEnvironment.filesystem,
      candidates, maximum: maximumEntries })
    : discover;
  const sourceObservations = new Map();

  function failure(key, error) {
    signal?.throwIfAborted();
    const message = error.message;
    onDiagnostic?.(message);
    return { type: 'failure', key, message };
  }

  function observe(definition, environment, key) {
    const identity = JSON.stringify(key);
    if (!sourceObservations.has(identity)) sourceObservations.set(identity, (async () => {
      try {
        const snapshot = await snapshotSource(definition, environment, key, limits, options);
        if (snapshot === null) return { type: 'absent', key };
        const previous = bindings.find(binding => isDeepStrictEqual(binding.key, key));
        return { type: 'present', snapshot, patch: proposeContextPatch(previous, snapshot) };
      // DEFENSE: File/metadata/diff-budget failures preserve the accepted binding and expose its diagnostic.
      } catch (error) { return failure(key, error); }
    })());
    return sourceObservations.get(identity);
  }

  async function observeDiscovery(definition, previous, plan) {
    const source = definition.observer;
    const descriptor = contextDescriptor(source);
    const skills = descriptor.skills;
    let entries;
    let configuration;
    try {
      if (skills) {
        configuration = await configurationResult;
        // DEFENSE: Failed configuration refresh cannot establish which explicitly configured skills to exclude.
        if (configuration.error) throw configuration.error;
      }
      entries = await (descriptor.workspace ? discoverWorkspace : discover)(source);
      if (skills) {
        const explicitDefinition = definitions.find(definition => definition.observer.type === 'config_files' && definition.observer.setting === 'skills');
        const explicit = new Set();
        for (const filename of configuration.value.skills) {
          const environment = { home: installation, workspace, filename: path.resolve(installation, filename) };
          const observed = await observe(explicitDefinition, environment, contextKey(explicitDefinition, environment));
          if (observed.type === 'present') explicit.add(environment.filename);
        }
        entries = boundary('control.context.filter', { entries, explicit: [...explicit] });
      }
      let collection = { observations: [], bytes: 0, maximum: source.policy.max_bytes, error: null };
      for (const entry of entries) {
        const environment = { home: installation, ...entry };
        const key = contextKey(definition, environment);
        const snapshot = await snapshotSource(definition, environment, key, limits, options);
        // DEFENSE: A candidate disappearing during a scan is not a complete collection
        // observation. Retry at the next request without withdrawing its peers.
        if (snapshot === null) throw new Error(`Context discovery source changed while being observed: ${entry.filename}`);
        const baseline = bindings.find(binding => isDeepStrictEqual(binding.key, key));
        collection = boundary('control.context.collect', { state: collection,
          bytes: Buffer.byteLength(JSON.stringify(snapshot.value), 'utf8'),
          observation: { type: 'present', snapshot, patch: proposeContextPatch(baseline, snapshot) } });
        if (collection.error !== null) break;
      }
      const observations = boundary('control.context.collection', { previous, state: collection,
        fallback: previous[0]?.key ?? contextKey(definition, { home: installation, workspace,
          filename: entries[0]?.filename ?? installation }), failure: null });
      for (const item of observations) if (item.type === 'failure') onDiagnostic?.(item.message);
      return observations;
    } catch (error) {
      // DEFENSE: An incomplete scan must preserve all previously accepted collection members and report failure.
      if (previous.length) return boundary('control.context.collection', { previous, state: { observations: [], bytes: 0, maximum: source.policy.max_bytes, error: null },
        fallback: null, failure: failure(previous[0].key, error).message });
      // DEFENSE: A collection with no accepted members still needs a valid source key
      // so a failed first scan is visible in the committed task history.
      const environment = { home: installation, workspace, filename: plan.fallback };
      const key = contextKey(definition, environment);
      return boundary('control.context.collection', { previous, state: { observations: [], bytes: 0, maximum: source.policy.max_bytes, error: null },
        fallback: key, failure: failure(key, error).message });
    }
  }

  try { return (await Promise.all(definitions.map(async definition => {
    const source = definition.observer;
    const previous = bindings.filter(binding => isDeepStrictEqual(binding.key.definition, definition));
    const plan = boundary('control.context.plan', { definition, home: installation, workspace, config: {} });
    if (!plan.active) {
      return previous.map(binding => ({ type: 'absent', key: binding.key }));
    }
    if (isContextDiscovery(source)) return observeDiscovery(definition, previous, plan);
    const needsConfiguration = plan.descriptor.configuration;
    const configured = needsConfiguration ? await configurationResult : { value: {} };
    const environment = { home: installation, workspace, config: configured.value };
    // DEFENSE: Invalid/unreadable configuration must report refresh failure without withdrawing accepted context.
    if (needsConfiguration && configured.error) {
      if (previous.length) return previous.map(binding => failure(binding.key, configured.error));
      // DEFENSE: Singleton identities independent of configuration can still identify a
      // failed first observation; list sources have no admitted members yet.
      if (source.type === 'config_files') return [];
      return [failure(contextKey(definition, environment), configured.error)];
    }
    const filePlan = boundary('control.context.plan', { definition, home: installation, workspace, config: environment.config });
    const base = filePlan.base === 'workspace' ? workspace : installation;
    const filenames = [...new Set(filePlan.filenames.map(filename => filename === null ? undefined : path.resolve(base, filename)))];
    const keys = filenames.map(filename => contextKey(definition, { ...environment, filename }));
    const observations = await Promise.all(filenames.map((filename, index) => observe(definition, { ...environment, filename }, keys[index])));
    observations.push(...previous.filter(binding => !keys.some(key => isDeepStrictEqual(binding.key, key)))
      .map(binding => ({ type: 'absent', key: binding.key })));
    return observations;
  }))).flat(); }
  finally { await workspaceEnvironment?.filesystem.close(); }
}
