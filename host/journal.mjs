import { DatabaseSync } from 'node:sqlite';
import { EventEmitter } from 'node:events';
import { createHash, randomBytes } from 'node:crypto';
import { chmod } from 'node:fs/promises';
import path from 'node:path';
import { Kernel, isKernelInputRejection } from './kernel.mjs';
import { integer } from './codec.mjs';
import { durableDirectory } from './control-records.mjs';
import { JournalCheckpoint } from './journal-checkpoint.mjs';

const outcomes = new WeakMap();
export const transactionOutcome = error => outcomes.get(error) ?? 'unknown';
export const isDefiniteRejection = error => transactionOutcome(error) === 'rejected';
function rejected(error, outcome) {
  outcomes.set(error, outcome);
  return error;
}

const replayVersion = 31;
export const journalFormat = `selvedge-rocq-journal-${replayVersion}`;
const journalSchemaVersion = 2;
const legacyVersions = new Map([28, 29, 30].map(version => [`selvedge-rocq-journal-${version}`, version]));
const checkpointInterval = 128;

const schema = {
  meta: 'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT',
  journal: 'CREATE TABLE journal (seq INTEGER PRIMARY KEY CHECK (seq > 0), input TEXT NOT NULL, observed_at INTEGER NOT NULL, replay_version INTEGER NOT NULL) STRICT',
};

function hashReplayRow(hash, row) {
  hash.update(`${row.seq}:${row.replay_version}:${Buffer.byteLength(row.input)}:`).update(row.input);
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

/** A serialized, durable input journal. It deliberately stores no task table. */
export class Journal extends EventEmitter {
  #database;
  #replayVersionColumn = 'replay_version';
  #lock;
  #kernel;
  #checkpoint;
  #checkpointAttemptSequence = 0;
  #prefix = createHash('sha256');
  #tail = Promise.resolve();
  #failure;
  #closing = false;

  static async open(filename, { waitForOwnership } = {}) {
    const journal = new Journal();
    journal.sequence = 0;
    journal.#checkpoint = new JournalCheckpoint(filename, journalFormat);
    try {
      let prepared;
      if (waitForOwnership) {
        prepared = await journal.#preload(filename);
        await waitForOwnership();
      }
      journal.#lock = await acquireJournalOwnership(filename);
      journal.#database = new DatabaseSync(filename, { timeout: 1000 });
      journal.#database.exec('PRAGMA synchronous=FULL');
      const upgrading = journal.#prepareReplay();
      await chmod(filename, 0o600);
      if (prepared) journal.#verifyPrefix(prepared);
      else await journal.#initializeReplay();
      await journal.#replay();
      journal.program = await journal.#kernel.observe();
      if (upgrading) {
        journal.#database.exec(`PRAGMA user_version = ${journalSchemaVersion}; COMMIT`);
      }
      journal.#database.exec('PRAGMA journal_mode=WAL');
      await journal.#maintainCheckpoint();
      return journal;
    // DEFENSE: Filesystem, SQLite or replay failures during open must release resources already acquired.
    } catch (error) {
      await journal.close();
      throw error;
    }
  }

  #prepareReplay(readOnly = false) {
    this.#replayVersionColumn = 'replay_version';
    const version = this.#database.prepare('PRAGMA user_version').get().user_version;
    // DEFENSE: A database or update candidate can use a newer schema.
    if (![0, 1, journalSchemaVersion].includes(version)) {
      throw new Error(`Unsupported Selvedge SQLite journal schema version ${version}`);
    }
    let upgrading = !readOnly && version !== journalSchemaVersion;
    if (upgrading) {
      this.#database.exec('BEGIN IMMEDIATE');
      if (version === 0 && !this.#database.prepare('SELECT 1 FROM sqlite_schema LIMIT 1').get()) {
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
    if (format.value !== journalFormat) {
      const legacy = legacyVersions.get(format.value);
      // DEFENSE: Only journals whose historical replay is implemented can be upgraded.
      const hasRowVersions = version === journalSchemaVersion;
      if (!legacy || hasRowVersions !== (legacy === 30)) {
        throw new Error(`Unsupported Selvedge Rocq journal format ${format.value}`);
      }
      if (readOnly) {
        if (!hasRowVersions) this.#replayVersionColumn = `${legacy} AS replay_version`;
      } else {
        if (!upgrading) {
          this.#database.exec('BEGIN IMMEDIATE');
          upgrading = true;
        }
        // An unversioned prefix belongs entirely to the format in its header.
        if (!hasRowVersions) {
          this.#database.exec(`ALTER TABLE journal ADD COLUMN replay_version INTEGER NOT NULL DEFAULT ${legacy}`);
        }
        this.#database.prepare("UPDATE meta SET value = ? WHERE key = 'format'").run(journalFormat);
      }
    } else if (version !== journalSchemaVersion && !upgrading) {
      // DEFENSE: An externally edited format tag cannot stand in for a completed upgrade.
      throw new Error('The current journal format requires its current schema version');
    }
    this.namespace = namespace.value;
    return upgrading;
  }

  async #preload(filename) {
    this.#database = new DatabaseSync(filename, { readOnly: true, timeout: 1000 });
    try {
      this.#database.exec('BEGIN');
      this.#prepareReplay(true);
      await this.#initializeReplay();
      await this.#replay();
      return { namespace: this.namespace, digest: this.#prefix.copy().digest('hex') };
    } finally {
      closeJournalDatabase(this.#database);
      this.#database = undefined;
    }
  }

  #readPrefix(sequence) {
    const hash = createHash('sha256');
    for (const row of this.#database.prepare(`SELECT seq, input, ${this.#replayVersionColumn} FROM journal WHERE seq <= ? ORDER BY seq`).iterate(sequence)) {
      hashReplayRow(hash, row);
    }
    return hash;
  }

  #verifyPrefix(prepared) {
    // DEFENSE: A journal replaced during the handoff can have a different history at the same cursor.
    if (this.namespace !== prepared.namespace || this.#readPrefix(this.sequence).digest('hex') !== prepared.digest) {
      throw new Error('The committed journal prefix changed during update preparation');
    }
  }

  async #initializeReplay() {
    this.#kernel = new Kernel();
    this.description = await this.#kernel.initialize();
    await this.#restoreCheckpoint();
  }

  async #restoreCheckpoint() {
    let image;
    try { image = await this.#checkpoint.read(this.namespace); }
    catch (error) {
      // DEFENSE: Cache-specific filesystem failures leave the committed input journal available.
      console.warn(`Journal checkpoint could not be read: ${error.message}`);
      return;
    }
    if (!image) return;
    const prefix = this.#readPrefix(image.sequence);
    // DEFENSE: A restored SQLite backup can be older than its sidecar checkpoint.
    if (prefix.copy().digest('hex') !== image.prefix) return;
    if (!await this.#kernel.restoreCheckpoint(image)) return;
    this.sequence = image.sequence;
    this.#checkpointAttemptSequence = image.sequence;
    this.#prefix = prefix;
  }

  async #maintainCheckpoint() {
    if (this.sequence === 0 || (this.#checkpointAttemptSequence !== 0 &&
      this.sequence - this.#checkpointAttemptSequence < checkpointInterval)) return;
    this.#checkpointAttemptSequence = this.sequence;
    // The journal queue still owns the Worker at the acknowledged sequence.
    const image = await this.#kernel.captureCheckpoint();
    try {
      await this.#checkpoint.write(this.namespace, this.sequence, this.#prefix.copy().digest('hex'), image);
    } catch (error) {
      // DEFENSE: The optional cache can fail to publish after the authoritative SQLite commit succeeded.
      console.warn(`Journal checkpoint could not be written: ${error.message}`);
    }
  }

  async #replay() {
    for (const row of this.#database.prepare(`SELECT seq, input, ${this.#replayVersionColumn} FROM journal WHERE seq > ? ORDER BY seq`).iterate(this.sequence)) {
      const durable = await this.#kernel.replay(row.input, row.replay_version);
      // DEFENSE: A stored input that the current kernel no longer admits cannot restore committed work.
      if (!durable) {
        throw new Error(`Committed input incompatibility at sequence ${row.seq}: current kernel rejected replay`);
      }
      hashReplayRow(this.#prefix, row);
      this.sequence = row.seq;
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
        const decision = { sequence: this.sequence, program: this.program, ...response.value };
        // Capture an authorized publication before the next input can replace this world.
        if (observeRead) observeRead(decision);
        // Noncommitting packets can only carry an in-process scheduler wakeup.
        if (decision.effects.length) this.#publish('transient', decision);
        return decision;
      }
      const sequence = this.sequence + 1;
      let committing = false;
      try {
        this.#database.exec('BEGIN IMMEDIATE');
        this.#database.prepare('INSERT INTO journal (seq, input, observed_at, replay_version) VALUES (?, ?, ?, ?)')
          .run(sequence, inputText, observedAt, replayVersion);
        committing = true;
        this.#database.exec('COMMIT');
      // DEFENSE: A write before COMMIT is definitely uncommitted; an error during COMMIT leaves its durable outcome unknown.
      } catch (error) {
        this.#poison(error, committing ? 'unknown' : 'rejected');
        throw error;
      }
      this.program = response.program;
      this.sequence = sequence;
      hashReplayRow(this.#prefix, { seq: sequence, input: inputText, replay_version: replayVersion });
      const committed = { sequence, program: this.program, ...response.value };
      this.#publish('commit', committed, browserRequest);
      return committed;
    });
    // DEFENSE: execute's caller receives the failure; queue cleanup must still reach close and later callers' explicit poisoned-world rejection.
    this.#tail = result.then(async decision => {
      if (decision.durable) {
        try { await this.#maintainCheckpoint(); }
        // DEFENSE: A crashed Worker cannot continue from its last commit even if capture exposed the failure.
        catch (error) { this.#poison(error); }
      }
    }, () => {});
    return result;
  }

  #publish(event, decision, browserRequest) {
    // DEFENSE: A delivery observer can throw after selection; it cannot undo a committed result.
    for (const observer of this.listeners(event)) {
      try { observer(decision, browserRequest); }
      catch (error) { this.emit('observerFailure', error); }
    }
  }

  observedAt(sequence) {
    return this.#database.prepare('SELECT observed_at FROM journal WHERE seq = ?').get(sequence).observed_at;
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
