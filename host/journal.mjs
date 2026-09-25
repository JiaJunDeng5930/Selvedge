import { DatabaseSync } from 'node:sqlite';
import { EventEmitter } from 'node:events';
import { createHash } from 'node:crypto';
import { mkdir, chmod, realpath } from 'node:fs/promises';
import path from 'node:path';
import { Kernel, buildIdentity } from './kernel.mjs';
import { parseJson, stringifyJson, integer } from './codec.mjs';

const schema = {
  meta: 'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT',
  journal: 'CREATE TABLE journal (seq INTEGER PRIMARY KEY CHECK (seq > 0), input TEXT NOT NULL, decision TEXT NOT NULL, previous TEXT NOT NULL, digest TEXT NOT NULL) STRICT',
};
const normalize = sql => sql.replace(/\s+/g, ' ').trim();
const identityKeys = ['format', 'compiler', 'fingerprint', 'workspace'];
const digest = (previous, sequence, input, decision) => createHash('sha256')
  .update(previous).update('\0').update(String(sequence)).update('\0')
  .update(input).update('\0').update(decision).digest('hex');

/** A serialized, durable input journal. It deliberately stores no task table. */
export class Journal extends EventEmitter {
  #database;
  #lock;
  #tail = Promise.resolve();
  #failure;
  #closing = false;
  #previous;

  static async open(filename, { kernelOptions, identity, cwd = process.cwd() } = {}) {
    const journal = new Journal();
    journal.filename = filename;
    journal.identity = { ...(identity ?? await buildIdentity()), workspace: await realpath(cwd) };
    journal.sequence = 0;
    journal.#previous = createHash('sha256').update(journal.identity.format).update(journal.identity.fingerprint)
      .update('\0').update(journal.identity.workspace).digest('hex');
    try {
      await mkdir(path.dirname(filename), { recursive: true, mode: 0o700 });
      // An OS-backed SQLite lock is released on process death. No stale-PID
      // heuristic is allowed to let two reconstructed worlds write one journal.
      journal.#lock = new DatabaseSync(`${filename}.lock`, { timeout: 0 });
      journal.#lock.exec('PRAGMA journal_mode=DELETE; CREATE TABLE IF NOT EXISTS owner (id INTEGER PRIMARY KEY); BEGIN EXCLUSIVE');
      journal.#database = new DatabaseSync(filename, { timeout: 1000 });
      await chmod(filename, 0o600);
      journal.#openSchema();
      journal.#database.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL');
      journal.kernel = new Kernel(kernelOptions);
      journal.description = await journal.kernel.initialize();
      for (const row of journal.#database.prepare('SELECT * FROM journal ORDER BY seq').iterate()) {
        if (row.seq !== journal.sequence + 1 || row.previous !== journal.#previous ||
            row.digest !== digest(row.previous, row.seq, row.input, row.decision)) {
          throw new Error(`Journal integrity failure at sequence ${row.seq}`);
        }
        const replayed = await journal.kernel.request(parseJson(row.input));
        if (!replayed.value.durable || replayed.text !== row.decision) {
          throw new Error(`Kernel replay disagrees with committed decision ${row.seq}`);
        }
        journal.sequence = row.seq;
        journal.#previous = row.digest;
      }
      return journal;
    } catch (error) {
      await journal.close();
      throw error;
    }
  }

  #openSchema() {
    const objects = this.#database.prepare("SELECT name, sql FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY name").all();
    if (objects.length === 0) {
      this.#database.exec('BEGIN IMMEDIATE');
      try {
        for (const sql of Object.values(schema)) this.#database.exec(sql);
        const insert = this.#database.prepare('INSERT INTO meta (key, value) VALUES (?, ?)');
        for (const key of identityKeys) insert.run(key, this.identity[key]);
        this.#database.exec('COMMIT');
      } catch (error) {
        this.#database.exec('ROLLBACK');
        throw error;
      }
    } else if (objects.length !== Object.keys(schema).length || objects.some(row => normalize(row.sql) !== normalize(schema[row.name] ?? ''))) {
      throw new Error('The database does not have the current Selvedge Bend journal schema');
    }
    const entries = this.#database.prepare('SELECT key, value FROM meta ORDER BY key').all();
    if (entries.length !== identityKeys.length || entries.some(row => this.identity[row.key] !== row.value)) {
      throw new Error('The database belongs to a different kernel, workspace, or persistent format; automatic conversion is not supported');
    }
  }

  #poison(error) {
    this.#failure = error;
    this.kernel?.abort(error);
  }

  execute(input) {
    if (this.#closing) return Promise.reject(new Error('Journal is closed'));
    const result = this.#tail.then(async () => {
      if (this.#failure) throw this.#failure;
      const inputText = stringifyJson(input);
      if (this.sequence >= Number.MAX_SAFE_INTEGER) throw new Error('Journal sequence exhausted');
      // Encoding failures occur before this returns a promise and cannot change
      // the kernel. Any asynchronous failure makes its resulting state unknown.
      const request = this.kernel.request(input);
      let response;
      try { response = await request; }
      catch (error) { this.#poison(error); throw error; }
      if (!response.value.durable) {
        if (response.value.effects.length !== 0) {
          const error = new Error('A nondurable decision attempted an effect');
          this.#poison(error);
          throw error;
        }
        return { sequence: this.sequence, ...response.value };
      }
      const sequence = this.sequence + 1;
      const hash = digest(this.#previous, sequence, inputText, response.text);
      try {
        this.#database.exec('BEGIN IMMEDIATE');
        this.#database.prepare('INSERT INTO journal (seq, input, decision, previous, digest) VALUES (?, ?, ?, ?, ?)')
          .run(sequence, inputText, response.text, this.#previous, hash);
        this.#database.exec('COMMIT');
      } catch (error) {
        try { this.#database.exec('ROLLBACK'); } catch {}
        this.#poison(error);
        throw error;
      }
      this.sequence = sequence;
      this.#previous = hash;
      const committed = { sequence, input, ...response.value };
      // Observer exceptions cannot roll back a committed decision or permit it
      // to be retried as an uncommitted input.
      for (const observer of this.listeners('commit')) {
        try { observer(committed); }
        catch (error) { this.emit('observerFailure', error); }
      }
      return committed;
    });
    this.#tail = result.catch(() => {});
    return result;
  }

  events(after, limit = 100) {
    integer(after, 'event cursor');
    integer(limit, 'event page size');
    if (after > this.sequence || limit < 1 || limit > 100) throw new RangeError('Invalid event page');
    return this.#database.prepare('SELECT seq FROM journal WHERE seq > ? ORDER BY seq LIMIT ?')
      .all(after, limit).map(row => ({ sequence: row.seq }));
  }

  async close() {
    if (this.#closing) return;
    this.#closing = true;
    await this.#tail;
    await this.kernel?.close();
    try { this.#database?.close(); }
    finally {
      try { this.#lock?.exec('ROLLBACK'); } catch {}
      this.#lock?.close();
    }
  }
}
