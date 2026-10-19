import { mkdir, writeFile, readFile, rename, rm, copyFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { compileJavaScript } from '../scripts/compile-javascript.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));

export async function fixtureRequest(name, source, exports) {
  const directory = path.join(repository, '.build', `test-${name}`);
  await mkdir(directory, { recursive: true });
  const entry = path.join(directory, 'fixture.bend');
  const output = path.join(directory, 'fixture.mjs');
  let previous;
  // DEFENSE: A named fixture has no previous entry on its first compilation.
  try { previous = await readFile(entry, 'utf8'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (previous !== source) {
    const temporary = `${entry}.${process.pid}.${randomUUID()}.tmp`;
    try {
      await writeFile(temporary, source);
      await rename(temporary, entry);
    } finally {
      await rm(temporary, { force: true });
    }
  }
  return { entry, output, sourceRoot: repository, exports };
}

export async function compiledFixture(name, source, exports) {
  return executeFixture(await fixtureRequest(name, source, exports));
}

async function executeFixture(request) {
  const { entry, output } = request;
  const directory = path.dirname(entry);
  const compiled = await compileJavaScript(request);
  // Bun retains file modules across query-string changes. A content-specific path
  // ensures a fixture rebuilt in this process executes its new code.
  const executable = path.join(directory, `fixture-${compiled.fingerprint}.mjs`);
  const temporary = `${executable}.${process.pid}.${randomUUID()}.tmp`;
  try {
    await copyFile(output, temporary);
    await rename(temporary, executable);
  } finally {
    await rm(temporary, { force: true });
  }
  return import(pathToFileURL(executable).href);
}
