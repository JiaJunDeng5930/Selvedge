import { readdir } from 'node:fs/promises';
import path from 'node:path';
import { root } from './build-tools.mjs';

const warnings = ['-w', '-register-all,-extraction-default-directory'];
const productionPath = ['-Q', 'theories', 'Selvedge'];
export const dependencyFlags = [...productionPath, '-Q', 'requirements', 'SelvedgeRequirements'];
export const productionFlags = [...warnings, ...productionPath];
const requirementFlags = [...warnings, ...dependencyFlags];

// Production cannot resolve requirement modules. Only their own compilation
// and dependency discovery receive the second logical root.
export const compilationFlags = filename => filename.startsWith('requirements/') ? requirementFlags : productionFlags;
export const moduleFile = name => name.startsWith('Requirements.')
  ? `requirements/${name.slice('Requirements.'.length).replaceAll('.', '/')}.v`
  : `theories/${name.replaceAll('.', '/')}.v`;
export const moduleName = filename => filename.startsWith('requirements/')
  ? `SelvedgeRequirements.${filename.slice('requirements/'.length, -2).replaceAll('/', '.')}`
  : `Selvedge.${filename.slice('theories/'.length, -2).replaceAll('/', '.')}`;
export const moduleSelection = filename => filename.startsWith('requirements/')
  ? `Requirements.${filename.slice('requirements/'.length, -2).replaceAll('/', '.')}`
  : filename.slice('theories/'.length, -2).replaceAll('/', '.');

async function files(directory) {
  const entries = await readdir(path.join(root, directory), { withFileTypes: true });
  return (await Promise.all(entries.map(entry => {
    const filename = `${directory}/${entry.name}`;
    return entry.isDirectory() ? files(filename) : filename.endsWith('.v') ? [filename] : [];
  }))).flat();
}

export async function sourceFiles() {
  return (await Promise.all(['theories', 'requirements'].map(files))).flat().sort();
}
