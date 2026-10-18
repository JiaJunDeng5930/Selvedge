import { createHash } from 'node:crypto';
import { realpath } from 'node:fs/promises';
import { isDeepStrictEqual } from 'node:util';
import path from 'node:path';
import { configurationFilename, contextConfiguration, defaultConfig } from './config.mjs';
import { snapshotContextFile } from './project.mjs';
import { proposeContextPatch } from './context-patches.mjs';

const configFileLimit = 1024 * 1024;

function revision(value) {
  return createHash('sha256').update(JSON.stringify(value), 'utf8').digest('hex');
}

function boundedText(value, field, maximum, required = false) {
  if (typeof value !== 'string' || !value.isWellFormed() || value.includes('\0') ||
    (required && !value.trim()) || Buffer.byteLength(value, 'utf8') > maximum) {
    throw new TypeError(`Context ${field} must be a ${required ? 'nonempty ' : ''}bounded UTF-8 string`);
  }
  return value;
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
    default: throw new TypeError('Unknown context identity source');
  }
}

function contextKey(definition, environment) {
  const identity = fieldRecord(definition.identity.map(field => [field.name,
    boundedText(identityValue(field.source, environment), field.name, 4096, field.required)]));
  return { type: definition.kind, definition, identity };
}

function metadataFields(content) {
  const frontmatter = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(content);
  if (!frontmatter) throw new TypeError('Context metadata requires YAML frontmatter');
  let metadata;
  try { metadata = Bun.YAML.parse(frontmatter[1]); }
  catch { throw new TypeError('Context frontmatter is not valid YAML'); }
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
      default: throw new TypeError('Unknown context field source');
    }
    return [field.name, boundedText(value, field.name, limits.project_context_bytes, field.required)];
  }));
  const value = { type: definition.kind, fields };
  return { key, revision: definition.observer.type === 'native_text' ? definition.observer.revision : revision(value), value };
}

async function mutableConfiguration(config, definitions, limits, options) {
  const filename = configurationFilename(config);
  if (filename === undefined) return contextConfiguration(config, definitions, limits);
  const file = await snapshotContextFile(filename, { ...limits, project_context_bytes: configFileLimit }, options);
  if (file === null) return contextConfiguration(defaultConfig, definitions, limits);
  let value;
  try { value = JSON.parse(file.content); }
  catch { throw new TypeError('Context configuration is not valid JSON'); }
  return contextConfiguration(value, definitions, limits);
}

/** Interpret native source descriptors; only the native history operation admits changes. */
export async function observeContextSources(effect, { home, config, limits, signal, onDiagnostic } = {}) {
  const installation = await realpath(home);
  const definitions = effect.definitions;
  if (!Array.isArray(definitions)) throw new TypeError('Native context source definitions are required');
  const bindings = effect.bindings;
  const options = { signal };
  const workspace = effect.settings.workspace.primary_root;
  const configuration = mutableConfiguration(config, definitions, limits, options);
  // An unreadable configuration must preserve its previous bindings while
  // independent file observations can still proceed.
  const configurationResult = configuration.then(value => ({ value }), error => ({ error }));

  function failure(key, error) {
    signal?.throwIfAborted();
    const message = error.message;
    onDiagnostic?.(message);
    return { type: 'failure', key, message };
  }

  async function observe(definition, environment, key) {
    try {
      const snapshot = await snapshotSource(definition, environment, key, limits, options);
      if (snapshot === null) return { type: 'absent', key };
      const previous = bindings.find(binding => isDeepStrictEqual(binding.key, key));
      return { type: 'present', snapshot, patch: proposeContextPatch(previous, snapshot) };
    } catch (error) { return failure(key, error); }
  }

  return (await Promise.all(definitions.map(async definition => {
    const source = definition.observer;
    const previous = bindings.filter(binding => isDeepStrictEqual(binding.key.definition, definition));
    if (definition.scope === 'workspace' && workspace === null) {
      return previous.map(binding => ({ type: 'absent', key: binding.key }));
    }
    const needsConfiguration = source.type === 'config_text' || source.type === 'config_files';
    const configured = needsConfiguration ? await configurationResult : {};
    const environment = { home: installation, workspace, config: configured.value ?? {} };
    if (needsConfiguration && configured.error) {
      if (previous.length) return previous.map(binding => failure(binding.key, configured.error));
      // Singleton identities independent of configuration can still identify a
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
      default: throw new TypeError('Unknown context observation strategy');
    }
    const keys = filenames.map(filename => contextKey(definition, { ...environment, filename }));
    const observations = await Promise.all(filenames.map((filename, index) => observe(definition, { ...environment, filename }, keys[index])));
    observations.push(...previous.filter(binding => !keys.some(key => isDeepStrictEqual(binding.key, key)))
      .map(binding => ({ type: 'absent', key: binding.key })));
    return observations;
  }))).flat();
}
