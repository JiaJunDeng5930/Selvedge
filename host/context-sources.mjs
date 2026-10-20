import { createHash } from 'node:crypto';
import { realpath } from 'node:fs/promises';
import { isDeepStrictEqual } from 'node:util';
import path from 'node:path';
import { configurationFilename, contextConfiguration, defaultConfig } from './config.mjs';
import { snapshotContextFile } from './project.mjs';
import { proposeContextPatch } from './context-patches.mjs';
import { boundary } from './public/model-boundary.mjs';
import { createContextDiscovery, isContextDiscovery } from './context-discovery.mjs';

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
  const content = definition.observer.type === 'native_text' ? definition.observer.content
    : definition.observer.type === 'config_text' ? environment.config[definition.observer.setting]
    : (await snapshotContextFile(environment.filename, limits, options))?.content;
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
export async function observeSkillCatalog(workspace, { home, config, limits, signal } = {}) {
  const definitions = boundary('config.context_definitions', {}).filter(definition =>
    definition.observer.type === 'home_skills' || definition.observer.type === 'workspace_skills'
    || (definition.observer.type === 'config_files' && definition.observer.setting === 'skills'));
  // NOTE: A first catalog has no accepted bindings on which the normal observer
  // can report a failed config_files refresh. Resolve it before observing files.
  const current = await mutableConfiguration(config, definitions, limits, { signal });
  const observations = await observeContextSources({ definitions, bindings: [], settings: { workspace } },
    { home, config: { ...config, ...current }, limits, signal });
  const failed = observations.find(observation => observation.type === 'failure');
  // DEFENSE: Incomplete or unreadable skill discovery must remain a visible
  // catalog failure rather than publishing a partial list as a complete result.
  if (failed) throw new Error(failed.message);
  return observations.filter(observation => observation.type === 'present')
    .map(observation => observation.snapshot.value.fields);
}

/** Interpret native source descriptors; only the native history operation admits changes. */
export async function observeContextSources(effect, { home, config, limits, signal, onDiagnostic } = {}) {
  const installation = await realpath(home);
  const definitions = effect.definitions;
  const bindings = effect.bindings;
  const options = { signal };
  const workspace = effect.settings.workspace.primary_root;
  const configuration = mutableConfiguration(config, definitions, limits, options);
  // DEFENSE: An unreadable configuration must preserve its previous bindings while
  // independent file observations can still proceed.
  const configurationResult = configuration.then(value => ({ value }), error => ({ error }));
  const discover = createContextDiscovery({ home: installation, settings: effect.settings, signal });
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

  async function observeDiscovery(definition, previous) {
    const source = definition.observer;
    const skills = source.type === 'home_skills' || source.type === 'workspace_skills';
    let entries;
    let configuration;
    try {
      if (skills) {
        configuration = await configurationResult;
        // DEFENSE: Failed configuration refresh cannot establish which explicitly configured skills to exclude.
        if (configuration.error) throw configuration.error;
      }
      entries = await discover(source);
      if (skills) {
        const explicitDefinition = definitions.find(definition => definition.observer.type === 'config_files' && definition.observer.setting === 'skills');
        const explicit = new Set();
        for (const filename of configuration.value.skills) {
          const environment = { home: installation, workspace, filename: path.resolve(installation, filename) };
          const observed = await observe(explicitDefinition, environment, contextKey(explicitDefinition, environment));
          if (observed.type === 'present') explicit.add(environment.filename);
        }
        entries = entries.filter(entry => !explicit.has(entry.filename));
      }
      const snapshots = [];
      let bytes = 0;
      for (const entry of entries) {
        const environment = { home: installation, ...entry };
        const key = contextKey(definition, environment);
        const snapshot = await snapshotSource(definition, environment, key, limits, options);
        // DEFENSE: A candidate disappearing during a scan is not a complete collection
        // observation. Retry at the next request without withdrawing its peers.
        if (snapshot === null) throw new Error(`Context discovery source changed while being observed: ${entry.filename}`);
        bytes += Buffer.byteLength(JSON.stringify(snapshot.value), 'utf8');
        // DEFENSE: Real skill/guidance collections can exceed the kernel's admitted aggregate byte budget.
        if (bytes > source.policy.max_bytes) throw new Error('Context discovery content budget exceeded');
        const baseline = bindings.find(binding => isDeepStrictEqual(binding.key, key));
        snapshots.push({ type: 'present', snapshot, patch: proposeContextPatch(baseline, snapshot) });
      }
      return [...snapshots, ...previous.filter(binding => !snapshots.some(item => isDeepStrictEqual(item.snapshot.key, binding.key)))
        .map(binding => ({ type: 'absent', key: binding.key }))];
    } catch (error) {
      // DEFENSE: An incomplete scan must preserve all previously accepted collection members and report failure.
      if (previous.length) return previous.map(binding => failure(binding.key, error));
      // DEFENSE: A collection with no accepted members still needs a valid source key
      // so a failed first scan is visible in the committed task history.
      const folder = source.type === 'home_guidance' ? installation : workspace ?? installation;
      const environment = { home: installation, workspace,
        filename: skills ? installation : path.join(folder, source.policy.files[0]) };
      return [failure(contextKey(definition, environment), error)];
    }
  }

  return (await Promise.all(definitions.map(async definition => {
    const source = definition.observer;
    const previous = bindings.filter(binding => isDeepStrictEqual(binding.key.definition, definition));
    if (['workspace', 'primary_workspace'].includes(definition.scope) && workspace === null) {
      return previous.map(binding => ({ type: 'absent', key: binding.key }));
    }
    if (isContextDiscovery(source)) return observeDiscovery(definition, previous);
    const needsConfiguration = source.type === 'config_text' || source.type === 'config_files';
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
    let filenames;
    switch (source.type) {
      case 'native_text':
      case 'config_text': filenames = [undefined]; break;
      case 'home_file': filenames = [path.resolve(installation, source.relative)]; break;
      case 'workspace_file': filenames = workspace === null ? [] : [path.resolve(workspace, source.relative)]; break;
      case 'config_files': filenames = [...new Set(environment.config[source.setting].map(filename => path.resolve(installation, filename)))]; break;
    }
    const keys = filenames.map(filename => contextKey(definition, { ...environment, filename }));
    const observations = await Promise.all(filenames.map((filename, index) => observe(definition, { ...environment, filename }, keys[index])));
    observations.push(...previous.filter(binding => !keys.some(key => isDeepStrictEqual(binding.key, key)))
      .map(binding => ({ type: 'absent', key: binding.key })));
    return observations;
  }))).flat();
}
