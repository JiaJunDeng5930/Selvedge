import { DatabaseSync } from 'node:sqlite';
import { EventEmitter } from 'node:events';
import { createHash, randomBytes } from 'node:crypto';
import { mkdir, chmod } from 'node:fs/promises';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { Kernel, isKernelInputRejection } from './kernel.mjs';
import { parseJson, stringifyJson, integer } from './codec.mjs';
import { durableDirectory } from './control-records.mjs';
import { boundary } from './public/model-boundary.mjs';

const outcomes = new WeakMap();
export const transactionOutcome = error => outcomes.get(error) ?? 'unknown';
export const isDefiniteRejection = error => transactionOutcome(error) === 'rejected';
function rejected(error, outcome) {
  outcomes.set(error, outcome);
  return error;
}

export const journalFormat = 'selvedge-rocq-journal-7';

const schema = {
  meta: 'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT',
  journal: 'CREATE TABLE journal (seq INTEGER PRIMARY KEY CHECK (seq > 0), input TEXT NOT NULL, decision TEXT NOT NULL, previous TEXT NOT NULL, digest TEXT NOT NULL) STRICT',
};
const normalize = sql => sql.replace(/\s+/g, ' ').trim();
const genesis = namespace => createHash('sha256').update(journalFormat).update('\0').update(namespace).digest('hex');
const digest = (previous, sequence, input, decision) => createHash('sha256')
  .update(previous).update('\0').update(String(sequence)).update('\0')
  .update(input).update('\0').update(decision).digest('hex');

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
  #control = boundary('control.transaction.initial', {});
  #database;
  #lock;
  #tail = Promise.resolve();
  #failure;
  #closing = false;
  #previous;

  static async open(filename, { kernelOptions } = {}) {
    const journal = new Journal();
    journal.filename = filename;
    journal.sequence = 0;
    try {
      await durableDirectory(path.dirname(filename));
      // DEFENSE: Two service processes can open the same home; SQLite excludes a second world writer and releases ownership on process death.
      journal.#lock = new DatabaseSync(`${filename}.lock`, { timeout: 0 });
      journal.#lock.exec('PRAGMA journal_mode=DELETE; CREATE TABLE IF NOT EXISTS owner (id INTEGER PRIMARY KEY); BEGIN EXCLUSIVE');
      journal.#database = new DatabaseSync(filename, { timeout: 1000 });
      await chmod(filename, 0o600);
      journal.#openSchema();
      journal.#previous = genesis(journal.namespace);
      journal.#database.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL');
      journal.kernel = new Kernel(kernelOptions);
      journal.description = await journal.kernel.initialize();
      journal.program = journal.kernel.initialProgram;
      for (const row of journal.#database.prepare('SELECT * FROM journal ORDER BY seq').iterate()) {
        // DEFENSE: Persisted rows can be truncated, reordered or edited outside the service; reject a broken hash chain before replay.
        if (row.seq !== journal.sequence + 1 || row.previous !== journal.#previous ||
            row.digest !== digest(row.previous, row.seq, row.input, row.decision)) {
          throw new Error(`Journal integrity failure at sequence ${row.seq}`);
        }
        const [request] = journal.#advance({ kind: 'begin', replay: true });
        const replayed = await journal.kernel.replay(parseJson(row.input));
        journal.#advance({ kind: 'worker_result', generation: request.generation, durable: true });
        journal.#advance({ kind: 'finish' });
        // DEFENSE: Saved decisions from a different kernel contract must fail reopen without executing their effects.
        if (!replayed.value.durable || !isDeepStrictEqual(replayed.value, parseJson(row.decision))) {
          throw new Error(`Committed decision incompatibility at sequence ${row.seq}: current kernel replay disagrees with the saved decision`);
        }
        journal.sequence = row.seq;
        journal.#previous = row.digest;
      }
      if (journal.sequence > 0) {
        const snapshot = await journal.kernel.request({ kind: 'command', command: { op: 'describe' } });
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
    const objects = this.#database.prepare("SELECT name, sql FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY name").all();
    if (objects.length === 0) {
      this.#database.exec('BEGIN IMMEDIATE');
      for (const sql of Object.values(schema)) this.#database.exec(sql);
      this.#database.prepare('INSERT INTO meta (key, value) VALUES (?, ?)').run('format', journalFormat);
      this.#database.prepare('INSERT INTO meta (key, value) VALUES (?, ?)').run('namespace', randomBytes(16).toString('hex'));
      this.#database.exec('COMMIT');
    // DEFENSE: A nonempty database can have an obsolete or foreign schema; accept only the current journal schema.
    } else if (objects.length !== Object.keys(schema).length || objects.some(row => normalize(row.sql) !== normalize(schema[row.name] ?? ''))) {
      throw new Error('The database does not have the current Selvedge Rocq journal schema');
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

  #advance(observation) {
    const transition = boundary('control.transaction.step', { state: this.#control, observation });
    this.#control = transition.state;
    return transition.effects;
  }

  #poison(error, observation = 'worker_failed') {
    const actions = this.#advance({ kind: observation });
    rejected(error, observation === 'commit_unknown' ? 'unknown' : 'rejected');
    this.#failure = error;
    if (actions.some(action => action.kind === 'retire')) {
      this.kernel?.abort(error);
      this.emit('retired', error);
    }
  }

  assess(candidate) {
    // DEFENSE: An assessment may be queued just before the journal closes.
    if (this.#closing) return Promise.reject(rejected(new Error('Journal is closed'), 'rejected'));
    const result = this.#tail.then(async () => {
      // DEFENSE: A failed prior commit leaves no authoritative world for a read-only assessment.
      if (this.#failure) throw this.#failure;
      const request = this.kernel.assess(candidate);
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
      let inputText;
      try { inputText = stringifyJson(input); }
      // DEFENSE: Invalid external JSON is rejected before any kernel transition or durable write.
      catch (error) { throw rejected(error, 'rejected'); }
      const [request] = this.#advance({ kind: 'begin', replay: false });
      let response;
      let pending;
      try { pending = this.kernel.request(input); }
      // DEFENSE: Encoding validates the input before the Worker receives its request.
      catch (error) {
        this.#advance({ kind: 'input_rejected', generation: request.generation });
        throw rejected(error, 'rejected');
      }
      try { response = await pending; }
      catch (error) {
        if (isKernelInputRejection(error)) {
          this.#advance({ kind: 'input_rejected', generation: request.generation });
        } else this.#poison(error);
        // No journal write has started, including when the Worker failed after advancing its private world.
        throw rejected(error, 'rejected');
      }
      const actions = this.#advance({ kind: 'worker_result', generation: request.generation, durable: response.value.durable });
      if (!actions.some(action => action.kind === 'commit')) {
        this.program = response.program;
        this.#advance({ kind: 'finish' });
        return { sequence: this.sequence, program: this.program, ...response.value };
      }
      const sequence = this.sequence + 1;
      const hash = digest(this.#previous, sequence, inputText, response.text);
      let committing = false;
      try {
        this.#database.exec('BEGIN IMMEDIATE');
        this.#database.prepare('INSERT INTO journal (seq, input, decision, previous, digest) VALUES (?, ?, ?, ?, ?)')
          .run(sequence, inputText, response.text, this.#previous, hash);
        committing = true;
        this.#database.exec('COMMIT');
      // DEFENSE: A write before COMMIT is definitely uncommitted; an error during COMMIT leaves its durable outcome unknown.
      } catch (error) {
        const outcome = committing ? 'unknown' : 'rejected';
        this.#poison(error, committing ? 'commit_unknown' : 'commit_rejected');
        throw rejected(error, outcome);
      }
      const publication = this.#advance({ kind: 'commit_ack' });
      this.program = response.program;
      this.sequence = sequence;
      this.#previous = hash;
      const committed = { sequence, input, program: this.program, ...response.value };
      this.#advance({ kind: 'finish' });
      // DEFENSE: A delivery observer can throw after COMMIT; report the delivery failure without making the durable input appear uncommitted.
      for (const observer of publication.some(action => action.kind === 'publish') ? this.listeners('commit') : []) {
        try { observer(committed); }
        catch (error) { this.emit('observerFailure', error); }
      }
      return committed;
    });
    // DEFENSE: execute's caller receives the failure; queue cleanup must still reach close and later callers' explicit poisoned-world rejection.
    this.#tail = result.catch(() => {});
    return result;
  }

  events(after, limit = 100) {
    integer(after, 'event cursor');
    integer(limit, 'event page size');
    // DEFENSE: Authenticated HTTP clients can request an unknown cursor or a page outside the supported 1..100 range.
    if (after > this.sequence || limit < 1 || limit > 100) throw new RangeError('Invalid event page');
    return this.#database.prepare('SELECT seq FROM journal WHERE seq > ? ORDER BY seq LIMIT ?')
      .all(after, limit).map(row => ({ sequence: row.seq }));
  }

  async close() {
    // DEFENSE: Startup cleanup and server shutdown can both close this journal.
    if (this.#closing) return;
    this.#closing = true;
    await this.#tail;
    this.#advance({ kind: 'close' });
    await this.kernel?.close();
    try { closeJournalDatabase(this.#database); }
    finally { closeJournalDatabase(this.#lock); }
  }
}
