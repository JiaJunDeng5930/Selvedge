import { createHash } from 'node:crypto';
import { realpath } from 'node:fs/promises';
import path from 'node:path';
import { configurationFilename, contextConfiguration, defaultConfig } from './config.mjs';
import { configuredInstructions, snapshotContextFile } from './project.mjs';
import { proposeContextPatch } from './context-patches.mjs';

const configFileLimit = 1024 * 1024;

function revision(content) {
  return createHash('sha256').update(content, 'utf8').digest('hex');
}

function sameKey(left, right) {
  if (left.type !== right.type) return false;
  switch (left.type) {
    case 'instruction': return left.origin === right.origin && left.path === right.path;
    case 'project_guidance': return left.workspace === right.workspace;
    case 'skill_information': return left.installation === right.installation && left.path === right.path;
    default: return false;
  }
}

function metadataText(value, field, maximum) {
  if (typeof value !== 'string' || !value.trim() || !value.isWellFormed() || value.includes('\0') || Buffer.byteLength(value, 'utf8') > maximum) {
    throw new TypeError(`Skill ${field} must be a nonempty bounded UTF-8 string`);
  }
  return value;
}

/** Reading a skill advertises its metadata; the body is not introduced. */
export async function snapshotSkillInformation(filename, installation, limits, options) {
  installation = await realpath(installation);
  filename = path.resolve(installation, filename);
  const file = await snapshotContextFile(filename, limits, options);
  if (file === null) return null;
  const frontmatter = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(file.content);
  if (!frontmatter) throw new TypeError('Skill information requires YAML frontmatter');
  let metadata;
  try { metadata = Bun.YAML.parse(frontmatter[1]); }
  catch { throw new TypeError('Skill frontmatter is not valid YAML'); }
  const maximum = limits.project_context_bytes;
  const value = {
    type: 'skill_information',
    name: metadataText(metadata?.name, 'name', maximum),
    description: metadataText(metadata?.description, 'description', maximum),
    path: filename,
  };
  const key = { type: 'skill_information', installation, path: filename };
  return { key, revision: revision(JSON.stringify(value)), value };
}

async function mutableConfiguration(config, limits, options) {
  const filename = configurationFilename(config);
  if (filename === undefined) return contextConfiguration(config);
  const file = await snapshotContextFile(filename, { ...limits, project_context_bytes: configFileLimit }, options);
  if (file === null) return contextConfiguration(defaultConfig);
  let value;
  try { value = JSON.parse(file.content); }
  catch { throw new TypeError('Context configuration is not valid JSON'); }
  return contextConfiguration(value);
}

/** Observations propose changes; the native history operation admits them. */
export async function observeContextSources(effect, { home, config, limits, signal, onDiagnostic } = {}) {
  const installation = await realpath(home);
  const bindings = effect.bindings;
  const options = { signal };
  const observations = [];
  const configuredKey = { type: 'instruction', origin: 'configured', path: '' };
  const globalKey = { type: 'instruction', origin: 'global_agents', path: path.join(installation, 'AGENTS.md') };

  function failure(key, error) {
    signal?.throwIfAborted();
    const message = error.message;
    onDiagnostic?.(message);
    return { type: 'failure', key, message };
  }

  async function observe(key, read) {
    try {
      const snapshot = await read();
      if (snapshot === null) return { type: 'absent', key };
      const previous = bindings.find(binding => sameKey(binding.key, key));
      return { type: 'present', snapshot, patch: proposeContextPatch(previous, snapshot) };
    } catch (error) { return failure(key, error); }
  }

  const configured = mutableConfiguration(config, limits, options);
  const workspace = effect.settings.workspace.primary_root;
  const files = [observe(globalKey, async () => {
    const file = await snapshotContextFile(globalKey.path, limits, options);
    return file === null ? null : { key: globalKey, revision: file.revision, value: { type: 'instruction', content: file.content } };
  })];
  if (workspace !== null) {
    const key = { type: 'project_guidance', workspace };
    files.push(observe(key, async () => {
      const file = await snapshotContextFile(path.join(workspace, 'AGENTS.md'), limits, options);
      return file === null ? null : { key, revision: file.revision, value: { type: 'project_guidance', content: file.content } };
    }));
  }

  let current;
  try {
    current = await configured;
    observations.push(await observe(configuredKey, async () => {
      const content = configuredInstructions(current, limits);
      return { key: configuredKey, revision: revision(content), value: { type: 'instruction', content } };
    }));
  } catch (error) {
    observations.push(failure(configuredKey, error));
    for (const binding of bindings) {
      if (binding.key.type === 'skill_information') observations.push(failure(binding.key, error));
    }
  }
  observations.push(...await Promise.all(files));
  if (current !== undefined) {
    const skillPaths = [...new Set(current.skills.map(filename => path.resolve(installation, filename)))];
    const skills = skillPaths.map(filename => {
      const key = { type: 'skill_information', installation, path: filename };
      return observe(key, () => snapshotSkillInformation(filename, installation, limits, options));
    });
    observations.push(...await Promise.all(skills));
    for (const binding of bindings) {
      if (binding.key.type === 'skill_information' && (binding.key.installation !== installation || !skillPaths.includes(binding.key.path))) {
        observations.push({ type: 'absent', key: binding.key });
      }
    }
  }
  return observations;
}
