import assert from 'node:assert/strict';
import { appendFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

const [filename, marker] = process.argv.slice(2);
const database = new DatabaseSync(filename, { readOnly: true });
const effects = database.prepare('SELECT decision FROM journal ORDER BY seq').all().flatMap(row => JSON.parse(row.decision).effects);
database.close();
assert.equal(effects.filter(effect => effect.kind === 'tool' && effect.call.id === 'bash-1').length, 1);
appendFileSync(marker, 'bash\n');
process.stdout.write('Bash result 世界 😀');
process.stderr.write('diagnostic');
