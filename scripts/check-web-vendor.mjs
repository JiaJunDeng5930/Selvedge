import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const directory = new URL('../host/public/vendor/', import.meta.url);
const manifest = JSON.parse(await readFile(new URL('manifest.json', directory), 'utf8'));
for (const dependency of manifest.packages) {
  if (!dependency.package || !dependency.version || !dependency.integrity.startsWith('sha512-')) throw new Error('Invalid web dependency manifest');
  for (const file of dependency.files) {
    if (!/^[a-zA-Z0-9.-]+$/.test(file.file)) throw new Error('Invalid vendored file path');
    const hash = createHash('sha256').update(await readFile(new URL(file.file, directory))).digest('hex');
    if (hash !== file.sha256) throw new Error(`Vendored web dependency differs from its recorded source: ${file.file}`);
  }
}
console.log('Pinned web dependency files match their manifest.');
