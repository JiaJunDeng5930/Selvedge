import assert from 'node:assert/strict';
import { appendFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

// This runs in the real approved subprocess, not in the service's test driver.
const [filename, marker, callId] = process.argv.slice(2);
const database = new DatabaseSync(filename, { readOnly: true });
let rows;
try {
  rows = database.prepare('SELECT seq, input, decision FROM journal ORDER BY seq').all()
    .map(row => ({ seq: row.seq, input: JSON.parse(row.input), decision: JSON.parse(row.decision) }));
} finally { database.close(); }
const executions = rows.flatMap(row => row.decision.effects
  .filter(effect => effect.kind === 'tool' && effect.call.id === callId)
  .map(effect => ({ seq: row.seq, effect })));
assert.equal(executions.length, 1, 'The execution must already have one durable authorization');
const { seq, effect } = executions[0];
assert.equal(effect.execution.access, 'unrestricted');
const reviews = rows.flatMap(row => {
  const command = row.input.command ?? row.input.event?.command;
  const review = row.input.kind === 'approval' ? {
    task: row.input.task_id, request: row.input.ticket, decision: row.input.outcome.decision,
  } : command?.op === 'review_approval' ? {
    task: command.task_id, request: command.operation_id, decision: command.decision,
  } : null;
  return review ? [{ seq: row.seq, ...review }] : [];
});
assert.ok(reviews.some(review => review.seq <= seq && review.task === effect.task_id &&
  review.request < effect.ticket && review.decision === 'allow'), 'The grant must be durable before this process starts');
assert.equal(process.cwd(), effect.execution.workspace.primary_root ?? '/');
appendFileSync(marker, 'ran\n');
process.stdout.write(JSON.stringify({ cwd: process.cwd(), ticket: effect.ticket }));
