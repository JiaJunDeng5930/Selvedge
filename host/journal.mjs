import { DatabaseSync } from 'node:sqlite';
import { EventEmitter } from 'node:events';
import { randomBytes } from 'node:crypto';
import { chmod } from 'node:fs/promises';
import path from 'node:path';
import { Kernel, isKernelInputRejection } from './kernel.mjs';
import { integer } from './codec.mjs';
import { durableDirectory } from './control-records.mjs';

const outcomes = new WeakMap();
export const transactionOutcome = error => outcomes.get(error) ?? 'unknown';
export const isDefiniteRejection = error => transactionOutcome(error) === 'rejected';
function rejected(error, outcome) {
  outcomes.set(error, outcome);
  return error;
}

export const journalFormat = 'selvedge-rocq-journal-28';
const journalSchemaVersion = 1;

const schema = {
  meta: 'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT',
  journal: 'CREATE TABLE journal (seq INTEGER PRIMARY KEY CHECK (seq > 0), input TEXT NOT NULL, observed_at INTEGER NOT NULL) STRICT',
};

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

/** A serialized, durable input journal. It deliberately stores no task table. */
export class Journal extends EventEmitter {
  #database;
  #lock;
  #kernel;
  #tail = Promise.resolve();
  #failure;
  #closing = false;

  static async open(filename) {
    const journal = new Journal();
    journal.sequence = 0;
    try {
      journal.#lock = await acquireJournalOwnership(filename);
      journal.#database = new DatabaseSync(filename, { timeout: 1000 });
      journal.#database.exec('PRAGMA synchronous=FULL');
      const upgrading = journal.#prepareReplay();
      await chmod(filename, 0o600);
      await journal.#replay();
      if (upgrading) {
        journal.#database.exec(`PRAGMA user_version = ${journalSchemaVersion}; COMMIT`);
      }
      journal.#database.exec('PRAGMA journal_mode=WAL');
      return journal;
    // DEFENSE: Filesystem, SQLite or replay failures during open must release resources already acquired.
    } catch (error) {
      await journal.close();
      throw error;
    }
  }

  #prepareReplay() {
    const version = this.#database.prepare('PRAGMA user_version').get().user_version;
    // DEFENSE: A different release or an external SQLite writer can set an unsupported storage version.
    if (version !== 0 && version !== journalSchemaVersion) {
      throw new Error(`Unsupported Selvedge SQLite journal schema version ${version}`);
    }
    if (version === 0) {
      this.#database.exec('BEGIN IMMEDIATE');
      const existing = this.#database.prepare('SELECT 1 FROM sqlite_schema LIMIT 1').get();
      if (!existing) {
        for (const sql of Object.values(schema)) this.#database.exec(sql);
        const insert = this.#database.prepare('INSERT INTO meta (key, value) VALUES (?, ?)');
        insert.run('format', journalFormat);
        insert.run('namespace', randomBytes(16).toString('hex'));
      }
    }
    const entries = this.#database.prepare('SELECT key, value FROM meta ORDER BY key').all();
    const [format, namespace] = entries;
    // DEFENSE: An externally edited or damaged database can lack a valid namespace or replay format.
    if (entries.length !== 2 || format.key !== 'format' || namespace.key !== 'namespace' ||
        !/^[0-9a-f]{32}$/.test(namespace.value)) {
      throw new Error('Invalid Selvedge journal metadata');
    }
    // DEFENSE: Earlier or later kernels can persist frames with different semantics.
    // A supported replay format conversion would rewrite the inputs and this tag in the transaction that spans replay.
    if (format.value !== journalFormat) {
      throw new Error(`Unsupported Selvedge Rocq journal format ${format.value}`);
    }
    this.namespace = namespace.value;
    return version === 0;
  }

  async #replay() {
    this.#kernel = new Kernel();
    const initial = await this.#kernel.initialize();
    this.description = initial.description;
    this.program = initial.program;
    for (const row of this.#database.prepare('SELECT seq, input FROM journal ORDER BY seq').iterate()) {
      const replayed = await this.#kernel.replay(row.input);
      // DEFENSE: A stored input that the current kernel no longer admits cannot restore committed work.
      if (!replayed.value.durable) {
        throw new Error(`Committed input incompatibility at sequence ${row.seq}: current kernel rejected replay`);
      }
      this.sequence = row.seq;
    }
    if (this.sequence > 0) {
      const snapshot = await this.#kernel.request({ kind: 'command', command: { op: 'describe' } }).result;
      this.program = snapshot.program;
    }
  }

  #poison(error, outcome = 'rejected') {
    rejected(error, outcome);
    this.#failure = error;
    this.#kernel.abort(error);
    this.emit('retired', error);
  }

  assess(candidate) {
    // DEFENSE: An assessment may be queued just before the journal closes.
    if (this.#closing) return Promise.reject(rejected(new Error('Journal is closed'), 'rejected'));
    const result = this.#tail.then(async () => {
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

  execute(input) {
    // DEFENSE: Requests already in flight at shutdown can still reach the journal.
    if (this.#closing) return Promise.reject(rejected(new Error('Journal is closed'), 'rejected'));
    const result = this.#tail.then(async () => {
      // DEFENSE: A prior SQLite/Worker failure leaves the in-memory world ahead of durable storage; never execute another input.
      if (this.#failure) throw this.#failure;
      const observedAt = Date.now();
      let inputText;
      let response;
      let pending;
      try {
        const submitted = this.#kernel.request(input);
        inputText = submitted.text;
        pending = submitted.result;
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
        this.program = response.program;
        return { sequence: this.sequence, program: this.program, ...response.value };
      }
      const sequence = this.sequence + 1;
      let committing = false;
      try {
        this.#database.exec('BEGIN IMMEDIATE');
        this.#database.prepare('INSERT INTO journal (seq, input, observed_at) VALUES (?, ?, ?)')
          .run(sequence, inputText, observedAt);
        committing = true;
        this.#database.exec('COMMIT');
      // DEFENSE: A write before COMMIT is definitely uncommitted; an error during COMMIT leaves its durable outcome unknown.
      } catch (error) {
        this.#poison(error, committing ? 'unknown' : 'rejected');
        throw error;
      }
      this.program = response.program;
      this.sequence = sequence;
      const committed = { sequence, program: this.program, ...response.value };
      // DEFENSE: A delivery observer can throw after COMMIT; report the delivery failure without making the durable input appear uncommitted.
      for (const observer of this.listeners('commit')) {
        try { observer(committed); }
        catch (error) { this.emit('observerFailure', error); }
      }
      return committed;
    });
    // DEFENSE: execute's caller receives the failure; queue cleanup must still reach close and later callers' explicit poisoned-world rejection.
    this.#tail = result.catch(() => {});
    return result;
  }

  observedAt(sequence) {
    return this.#database.prepare('SELECT observed_at FROM journal WHERE seq = ?').get(sequence).observed_at;
  }

  events(after, limit = 100) {
    integer(after, 'event cursor');
    integer(limit, 'event page size');
    // DEFENSE: Authenticated HTTP clients can request an unknown cursor or a page outside the supported 1..100 range.
    if (after > this.sequence || limit < 1 || limit > 100) throw new RangeError('Invalid event page');
    return this.#database.prepare('SELECT seq FROM journal WHERE seq > ? ORDER BY seq LIMIT ?')
      .all(after, limit).map(row => ({ sequence: row.seq }));
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
