import assert from 'node:assert/strict';
import { appendFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

const [filename, marker] = process.argv.slice(2);
const database = new DatabaseSync(filename, { readOnly: true });
const row = database.prepare('SELECT decision FROM journal ORDER BY seq DESC LIMIT 1').get();
database.close();
assert.ok(JSON.parse(row.decision).effects.some(effect => effect.kind === 'tool' && effect.call.id === 'bash-1'));
appendFileSync(marker, 'bash\n');
process.stdout.write('Bash result 世界 😀');
process.stderr.write('diagnostic');
