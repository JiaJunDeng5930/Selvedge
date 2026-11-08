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
      await durableDirectory(path.dirname(filename));
      // DEFENSE: Two service processes can open the same home; SQLite excludes a second world writer and releases ownership on process death.
      journal.#lock = new DatabaseSync(`${filename}.lock`, { timeout: 0 });
      journal.#lock.exec('PRAGMA journal_mode=DELETE; CREATE TABLE IF NOT EXISTS owner (id INTEGER PRIMARY KEY); BEGIN EXCLUSIVE');
      journal.#database = new DatabaseSync(filename, { timeout: 1000 });
      await chmod(filename, 0o600);
      journal.#openSchema();
      journal.#database.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL');
      journal.#kernel = new Kernel();
      const initial = await journal.#kernel.initialize();
      journal.description = initial.description;
      journal.program = initial.program;
      for (const row of journal.#database.prepare('SELECT seq, input FROM journal ORDER BY seq').iterate()) {
        const replayed = await journal.#kernel.replay(row.input);
        // DEFENSE: A stored input that the current kernel no longer admits cannot restore committed work.
        if (!replayed.value.durable) {
          throw new Error(`Committed input incompatibility at sequence ${row.seq}: current kernel rejected replay`);
        }
        journal.sequence = row.seq;
      }
      if (journal.sequence > 0) {
        const snapshot = await journal.#kernel.request({ kind: 'command', command: { op: 'describe' } }).result;
        journal.program = snapshot.program;
      }
      return journal;
    // DEFENSE: Filesystem, SQLite or replay failures during open must release resources already acquired.
    } catch (error) {
      await journal.close();
      throw error;
    }
  }

  #openSchema() {
    const existing = this.#database.prepare('SELECT 1 FROM sqlite_schema LIMIT 1').get();
    if (!existing) {
      this.#database.exec('BEGIN IMMEDIATE');
      for (const sql of Object.values(schema)) this.#database.exec(sql);
      this.#database.prepare('INSERT INTO meta (key, value) VALUES (?, ?)').run('format', journalFormat);
      this.#database.prepare('INSERT INTO meta (key, value) VALUES (?, ?)').run('namespace', randomBytes(16).toString('hex'));
      this.#database.exec('COMMIT');
    }
    const entries = this.#database.prepare('SELECT key, value FROM meta ORDER BY key').all();
    // DEFENSE: Existing databases can have unknown formats or damaged namespace metadata; they must fail without conversion.
    if (entries.length === 2 && entries[0].key === 'format' && entries[0].value === journalFormat &&
        entries[1].key === 'namespace' && /^[0-9a-f]{32}$/.test(entries[1].value)) {
      this.namespace = entries[1].value;
      return;
    }
    throw new Error('The database does not have the current Selvedge Rocq journal format');
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

  async close() {
    // DEFENSE: Startup cleanup and server shutdown can both close this journal.
    if (this.#closing) return;
    this.#closing = true;
    await this.#tail;
    await this.#kernel?.close();
    try { closeJournalDatabase(this.#database); }
    finally { closeJournalDatabase(this.#lock); }
  }
}
