import { mkdtemp, mkdir, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { compileJavaScript } from '../scripts/compile-javascript.mjs';
import { prepareUiVerification } from '../scripts/ui-verification.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));

/** Compile the production operations needed by native-browser boundary fixtures. */
export async function browserBoundaryModel(t) {
  await mkdir(path.join(repository, '.workpad'), { recursive: true });
  const directory = await mkdtemp(path.join(repository, '.workpad', 'browser-boundary-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const output = path.join(directory, 'boundary.mjs');
  const { runtimeEntry } = prepareUiVerification(repository);
  await compileJavaScript({ entry: runtimeEntry, output, exports: {
    service_initial: 'interaction/services/MODEL.initial', service_step: 'interaction/services/MODEL.step', native_editor_key: 'browser/editor/MODEL.native_key',
  } });
  return { module: await import(pathToFileURL(output).href), output };
}
