import { DatabaseSync } from 'node:sqlite';
import { EventEmitter } from 'node:events';
import { randomBytes } from 'node:crypto';
import { chmod } from 'node:fs/promises';
import path from 'node:path';
import { Kernel, isKernelInputRejection } from './kernel.mjs';
import { integer } from './codec.mjs';
import { durableDirectory } from './control-records.mjs';
import { applyProgramUpdates } from './public/program-updates.mjs';

const retainedProgramUpdates = 16;

const outcomes = new WeakMap();
export const transactionOutcome = error => outcomes.get(error) ?? 'unknown';
export const isDefiniteRejection = error => transactionOutcome(error) === 'rejected';
function rejected(error, outcome) {
  outcomes.set(error, outcome);
  return error;
}

export const stateSchemaVersion = 3;

const schema = `
  CREATE TABLE state (
    id INTEGER PRIMARY KEY CHECK (id = 1), namespace TEXT NOT NULL,
    schema TEXT NOT NULL, sequence INTEGER NOT NULL CHECK (sequence >= 0), data BLOB NOT NULL
  ) STRICT;
  CREATE TABLE tasks (
    id INTEGER PRIMARY KEY CHECK (id >= 0), created_at INTEGER NOT NULL, data BLOB NOT NULL
  ) STRICT;
`;

function readState(database) {
  // DEFENSE: The database can contain an earlier input journal or a newer schema.
  const version = database.prepare('PRAGMA user_version').get().user_version;
  if (version !== stateSchemaVersion) throw new Error(`Unsupported Selvedge SQLite state schema version ${version}`);
  const record = database.prepare('SELECT namespace, schema, sequence, data FROM state WHERE id = 1').get();
  // DEFENSE: An externally edited database cannot supply missing or invalid service identity.
  if (!record || !/^[0-9a-f]{32}$/.test(record.namespace)) throw new Error('Invalid Selvedge state metadata');
  const tasks = database.prepare('SELECT id, data FROM tasks ORDER BY id').all().map((row, index) => {
    // DEFENSE: A missing row must not silently assign the next task a different identity.
    if (row.id !== index) throw new Error('Invalid Selvedge stored task identities');
    return Buffer.from(row.data).toString('latin1');
  });
  return { namespace: record.namespace, schema: record.schema, sequence: integer(record.sequence, 'state sequence'),
    shared: Buffer.from(record.data).toString('latin1'), tasks };
}

function closeJournalDatabase(database) {
  // DEFENSE: Failed startup can reach cleanup before either SQLite handle was opened.
  if (!database) return;
  try {
    // DEFENSE: A failed INSERT/COMMIT or the ownership lock can leave a live transaction; Bun may defer close until prepared statements are collected, retaining that transaction's lock.
    if (database.isTransaction) database.exec('ROLLBACK');
  } finally { database.close(); }
}

async function acquireJournalOwnership(filename) {
  await durableDirectory(path.dirname(filename));
  const lock = new DatabaseSync(`${filename}.lock`, { timeout: 0 });
  try {
    lock.exec('PRAGMA journal_mode=DELETE; CREATE TABLE IF NOT EXISTS owner (id INTEGER PRIMARY KEY); BEGIN EXCLUSIVE');
    return lock;
  // DEFENSE: A service or offline update already holding this lock excludes another owner.
  } catch (error) {
    closeJournalDatabase(lock);
    throw error;
  }
}

/** Run an offline journal operation under the same lock the live service holds. */
export async function withJournalOwnership(filename, action) {
  const lock = await acquireJournalOwnership(filename);
  try { return await action(); }
  finally { closeJournalDatabase(lock); }
}

/** Serializes kernel decisions through the SQLite commit and publication. */
export class Journal extends EventEmitter {
  #database;
  #lock;
  #kernel;
  #tail = Promise.resolve();
  #programUpdates = [];
  #failure;
  #closing = false;

  static async open(filename, { waitForOwnership } = {}) {
    const journal = new Journal();
    journal.#kernel = new Kernel();
    try {
      journal.description = await journal.#kernel.initialize();
      let preparedNamespace;
      if (waitForOwnership) {
        const reader = new DatabaseSync(filename, { readOnly: true, timeout: 1000 });
        try {
          reader.exec('BEGIN');
          const prepared = readState(reader);
          await journal.#kernel.loadState(prepared);
          preparedNamespace = prepared.namespace;
        } finally { closeJournalDatabase(reader); }
        await waitForOwnership();
      }
      journal.#lock = await acquireJournalOwnership(filename);
      journal.#database = new DatabaseSync(filename, { timeout: 1000 });
      journal.#database.exec('PRAGMA synchronous=FULL; BEGIN IMMEDIATE');
      const version = journal.#database.prepare('PRAGMA user_version').get().user_version;
      if (version === 0 && !journal.#database.prepare('SELECT 1 FROM sqlite_schema LIMIT 1').get()) {
        // DEFENSE: During handoff the store must still belong to the prepared service.
        if (preparedNamespace !== undefined) throw new Error('The Selvedge state database changed during update preparation');
        const { program, storage } = await journal.#kernel.loadState(null);
        journal.namespace = randomBytes(16).toString('hex');
        journal.sequence = 0;
        journal.program = program;
        journal.#database.exec(schema);
        journal.#database.prepare('INSERT INTO state VALUES (1, ?, ?, 0, ?)')
          .run(journal.namespace, storage.schema, Buffer.from(storage.shared, 'latin1'));
        journal.#database.exec(`PRAGMA user_version = ${stateSchemaVersion}`);
      } else {
        const state = readState(journal.#database);
        // DEFENSE: A replacement store cannot take over the prepared service.
        if (preparedNamespace !== undefined && preparedNamespace !== state.namespace) {
          throw new Error('The Selvedge state database changed during update preparation');
        }
        // Read the final committed records after ownership transfers.
        const { program } = await journal.#kernel.loadState(state);
        Object.assign(journal, { namespace: state.namespace, sequence: state.sequence, program });
      }
      await chmod(filename, 0o600);
      journal.#database.exec('COMMIT; PRAGMA journal_mode=WAL');
      return journal;
    // DEFENSE: Filesystem, SQLite or decoder failures during open must release acquired resources.
    } catch (error) {
      await journal.close();
      throw error;
    }
  }

  #poison(error, outcome = 'rejected') {
    rejected(error, outcome);
    this.#failure = error;
    this.#kernel.abort(error);
    this.emit('retired', error);
  }

  assess(candidate, { signal } = {}) {
    // DEFENSE: An assessment may be queued just before the journal closes.
    if (this.#closing) return Promise.reject(rejected(new Error('Journal is closed'), 'rejected'));
    const result = this.#tail.then(async () => {
      // DEFENSE: A browser can cancel a stale observation before its turn in the journal.
      signal?.throwIfAborted();
      // DEFENSE: A failed prior commit leaves no authoritative world for a read-only assessment.
      if (this.#failure) throw this.#failure;
      const request = this.#kernel.assess(candidate);
      try { return (await request).value; }
      // DEFENSE: A worker failure during assessment retires that world, so later journal commands must also fail.
      catch (error) { if (!isKernelInputRejection(error)) this.#poison(error); throw error; }
    });
    // DEFENSE: The returned promise reports the failure; close must still wait for this queued assessment.
    this.#tail = result.catch(() => {});
    return result;
  }

  execute(input, observeRead, browserRequest) {
    // DEFENSE: Requests already in flight at shutdown can still reach the journal.
    if (this.#closing) return Promise.reject(rejected(new Error('Journal is closed'), 'rejected'));
    const result = this.#tail.then(async () => {
      // DEFENSE: A prior SQLite/Worker failure leaves the in-memory world ahead of durable storage; never execute another input.
      if (this.#failure) throw this.#failure;
      const observedAt = Date.now();
      let response;
      let pending;
      try {
        pending = this.#kernel.request(input);
      }
      // DEFENSE: Invalid or oversized external JSON fails before the Worker receives a frame or a journal write starts.
      catch (error) {
        throw rejected(error, 'rejected');
      }
      try { response = await pending; }
      catch (error) {
        if (isKernelInputRejection(error)) {
          rejected(error, 'rejected');
        } else this.#poison(error);
        // No journal write has started, including when the Worker failed after advancing its private world.
        throw error;
      }
      if (!response.value.durable) {
        const decision = { sequence: this.sequence, program: this.program, ...response.value };
        // Capture an authorized publication before the next input can replace this world.
        if (observeRead) observeRead(decision);
        // Noncommitting packets can only carry an in-process scheduler wakeup.
        if (decision.effects.length) this.#publish('transient', decision);
        return decision;
      }
      const sequence = this.sequence + 1;
      let program;
      let committing = false;
      try {
        program = applyProgramUpdates(this.program, [response.programUpdate]);
        this.#database.exec('BEGIN IMMEDIATE');
        const { shared, tasks } = response.storage;
        const writeTask = this.#database.prepare(`
          INSERT INTO tasks (id, created_at, data) VALUES (?, ?, ?)
          ON CONFLICT (id) DO UPDATE SET data = excluded.data
        `);
        for (const task of tasks) writeTask.run(task.id, observedAt, Buffer.from(task.data, 'latin1'));
        this.#database.prepare('UPDATE state SET sequence = ?, data = coalesce(?, data) WHERE id = 1')
          .run(sequence, shared === null ? null : Buffer.from(shared, 'latin1'));
        committing = true;
        this.#database.exec('COMMIT');
      // DEFENSE: A write before COMMIT is definitely uncommitted; an error during COMMIT leaves its durable outcome unknown.
      } catch (error) {
        this.#poison(error, committing ? 'unknown' : 'rejected');
        throw error;
      }
      this.program = program;
      this.sequence = sequence;
      this.#programUpdates.push(response.programUpdate);
      if (this.#programUpdates.length > retainedProgramUpdates) this.#programUpdates.shift();
      const committed = { sequence, program: this.program, ...response.value };
      this.#publish('commit', committed, browserRequest);
      return committed;
    });
    // DEFENSE: execute's caller receives the failure; queue cleanup must still reach close and later callers' explicit poisoned-world rejection.
    this.#tail = result.catch(() => {});
    return result;
  }

  #publish(event, decision, browserRequest) {
    // DEFENSE: A delivery observer can throw after selection; it cannot undo a committed result.
    for (const observer of this.listeners(event)) {
      try { observer(decision, browserRequest); }
      catch (error) { this.emit('observerFailure', error); }
    }
  }

  taskCreatedAt(taskId) {
    return this.#database.prepare('SELECT created_at FROM tasks WHERE id = ?').get(integer(taskId, 'task ID')).created_at;
  }

  programUpdates(after, through) {
    if (!Number.isSafeInteger(after) || after > through || through > this.sequence) return undefined;
    if (after === through) return [];
    const base = this.sequence - this.#programUpdates.length;
    if (after < base) return undefined;
    return this.#programUpdates.slice(after - base, through - base);
  }

  assertEventCursor(after) {
    integer(after, 'event cursor');
    // DEFENSE: An authenticated subscription can request a cursor beyond its current journal.
    if (after > this.sequence) throw new RangeError('Invalid event page');
  }

  events(after, limit = 100) {
    this.assertEventCursor(after);
    integer(limit, 'event page size');
    // DEFENSE: An authenticated history request can ask for a page outside the supported 1..100 range.
    if (limit < 1 || limit > 100) throw new RangeError('Invalid event page');
    const first = Math.max(1, after + 1);
    return Array.from({ length: Math.min(limit, this.sequence - first + 1) }, (_, index) => ({ sequence: first + index }));
  }

  abort(error) { this.#kernel.abort(error); }

  whenIdle() { return this.#tail; }

  async close() {
    // DEFENSE: Startup cleanup and server shutdown can both close this journal.
    if (this.#closing) return;
    this.#closing = true;
    try {
      await this.whenIdle();
      await this.#kernel?.close();
    } finally {
      try { closeJournalDatabase(this.#database); }
      finally { closeJournalDatabase(this.#lock); }
    }
  }
}
