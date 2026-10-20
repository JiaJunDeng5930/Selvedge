import { DatabaseSync } from 'node:sqlite';
import { EventEmitter } from 'node:events';
import { createHash, randomBytes } from 'node:crypto';
import { mkdir, chmod } from 'node:fs/promises';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { Kernel } from './kernel.mjs';
import { parseJson, stringifyJson, integer } from './codec.mjs';

export const journalFormat = 'selvedge-bend-journal-8';

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
      await mkdir(path.dirname(filename), { recursive: true, mode: 0o700 });
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
        const replayed = await journal.kernel.replay(parseJson(row.input));
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
      throw new Error('The database does not have the current Selvedge Bend journal schema');
    }
    const entries = this.#database.prepare('SELECT key, value FROM meta ORDER BY key').all();
    // DEFENSE: Existing databases can have unknown formats or damaged namespace metadata; they must fail without conversion.
    if (entries.length === 2 && entries[0].key === 'format' && entries[0].value === journalFormat &&
        entries[1].key === 'namespace' && /^[0-9a-f]{32}$/.test(entries[1].value)) {
      this.namespace = entries[1].value;
      return;
    }
    throw new Error('The database does not have the current Selvedge Bend journal format');
  }

  #poison(error) {
    this.#failure = error;
    this.kernel?.abort(error);
  }

  execute(input) {
    // DEFENSE: Requests already in flight at shutdown can still reach the journal.
    if (this.#closing) return Promise.reject(new Error('Journal is closed'));
    const result = this.#tail.then(async () => {
      // DEFENSE: A prior SQLite/Worker failure leaves the in-memory world ahead of durable storage; never execute another input.
      if (this.#failure) throw this.#failure;
      const inputText = stringifyJson(input);
      // Encoding failures occur before this returns a promise and cannot change
      // the kernel. Any asynchronous failure makes its resulting state unknown.
      const request = this.kernel.request(input);
      let response;
      try { response = await request; }
      // DEFENSE: An asynchronous Worker failure can occur after its state advanced; this journal cannot keep accepting inputs.
      catch (error) { this.#poison(error); throw error; }
      if (!response.value.durable) {
        this.program = response.program;
        return { sequence: this.sequence, program: this.program, ...response.value };
      }
      const sequence = this.sequence + 1;
      const hash = digest(this.#previous, sequence, inputText, response.text);
      try {
        this.#database.exec('BEGIN IMMEDIATE');
        this.#database.prepare('INSERT INTO journal (seq, input, decision, previous, digest) VALUES (?, ?, ?, ?, ?)')
          .run(sequence, inputText, response.text, this.#previous, hash);
        this.#database.exec('COMMIT');
      // DEFENSE: SQLite can fail after the kernel advances; poison that world before any later input and release its remaining transaction during close.
      } catch (error) {
        this.#poison(error);
        throw error;
      }
      this.program = response.program;
      this.sequence = sequence;
      this.#previous = hash;
      const committed = { sequence, input, program: this.program, ...response.value };
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
    await this.kernel?.close();
    try { closeJournalDatabase(this.#database); }
    finally { closeJournalDatabase(this.#lock); }
  }
}
