import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { mkdir, open, lstat } from 'node:fs/promises';
import { existsSync, lstatSync } from 'node:fs';
import path from 'node:path';
import { boundary } from './public/model-boundary.mjs';

function closeDatabase(db) {
  try {
    // DEFENSE: Metadata or receipt rejection can leave BEGIN IMMEDIATE active; Bun can defer close while statements remain reachable.
    if (db.isTransaction) db.exec('ROLLBACK');
  } finally { db.close(); }
}

export function retainedRequest(record) {
  const value = boundary('web.retained', { record });
  const error = new Error(value.message);
  error.name = 'ChatGPTWebRetainedRequest';
  error.requestKey = value.request_key;
  error.responseId = value.response_id;
  return error;
}

// This database records external request receipts, not task lifecycle. A native
// ticket authorizes creation; replay never calls this interpreter. Commit the
// original body/key before HTTP so an unknown outcome cannot acquire a new key.
export class WebRequestStore {
  static resetExisting(home, taskId) {
    const filename = path.join(home, 'providers', 'chatgpt-web', 'requests.sqlite');
    if (!existsSync(filename)) return;
    const info = lstatSync(filename);
    // DEFENSE: A local receipt path can be replaced by a symlink or directory; never open that object as the private database.
    if (!info.isFile()) throw new Error('Invalid ChatGPT Web receipt database');
    const db = new DatabaseSync(filename);
    try {
      db.exec('PRAGMA busy_timeout=5000; PRAGMA synchronous=FULL; BEGIN IMMEDIATE');
      const rows = db.prepare('SELECT * FROM metadata').all();
      const records = db.prepare('SELECT * FROM requests WHERE owner=?').all(`task:${taskId}`);
      const writes = boundary('web.reset_session', { rows, records, task_id: taskId,
        created: false, new_identity: randomUUID() });
      for (const write of writes) {
        db.prepare('UPDATE requests SET retired=? WHERE request_key=?').run(write.updates.retired, write.request_key);
      }
      db.exec('COMMIT');
    } finally { closeDatabase(db); }
  }

  static retireExisting(home, owner, ticket) {
    // Snapshot the target before yielding: a later task input must not cause
    // cancellation to retarget a newly admitted successor.
    const filename = path.join(home, 'providers', 'chatgpt-web', 'requests.sqlite');
    if (!existsSync(filename)) return null;
    // DEFENSE: Cancellation can encounter a receipt path replaced by a symlink or directory; reject it before SQLite follows it.
    if (!lstatSync(filename).isFile()) throw new Error('Invalid ChatGPT Web receipt database');
    const db = new DatabaseSync(filename);
    try {
      db.exec('PRAGMA busy_timeout=5000; PRAGMA synchronous=FULL; BEGIN IMMEDIATE');
      const rows = db.prepare('SELECT * FROM metadata').all();
      const source = { rows, created: false, new_identity: randomUUID() };
      boundary('web.store_metadata', source);
      const records = db.prepare('SELECT * FROM requests WHERE owner=?').all(owner);
      const selected = boundary('web.retire_existing', { ...source, records, owner, ticket });
      for (const write of selected) {
        db.prepare('UPDATE requests SET retired=? WHERE request_key=?').run(write.updates.retired, write.request_key);
      }
      const record = selected[0]?.record;
      db.exec('COMMIT');
      return record;
    } finally { closeDatabase(db); }
  }

  static async open(home, { create = true } = {}) {
    const directory = path.join(home, 'providers', 'chatgpt-web');
    const filename = path.join(directory, 'requests.sqlite');
    if (create) await mkdir(directory, { recursive: true, mode: 0o700 });
    let created = false;
    try {
      const info = await lstat(filename);
      // DEFENSE: A persisted receipt path can be replaced by a symlink or directory; it cannot be admitted as a private SQLite file.
      if (!info.isFile()) throw new Error('Invalid ChatGPT Web receipt database');
    } catch (error) {
      // DEFENSE: Only an absent receipt file can be created; permission and wrong-file-type failures must propagate.
      if (error.code !== 'ENOENT') throw error;
      if (!create) return null;
      const file = await open(filename, 'ax', 0o600).catch(error => {
        // DEFENSE: Concurrent model effects can both observe ENOENT; only the first creates the shared receipt database.
        if (error.code !== 'EEXIST') throw error;
        return null;
      });
      created = file !== null;
      await file?.close();
    }
    const db = new DatabaseSync(filename);
    try {
      db.exec('PRAGMA busy_timeout=5000; PRAGMA synchronous=FULL; BEGIN IMMEDIATE');
      const rows = created ? [] : db.prepare('SELECT * FROM metadata').all();
      const metadata = boundary('web.store_metadata', { rows, created, new_identity: randomUUID() });
      if (created) {
        db.exec(`CREATE TABLE metadata (format TEXT NOT NULL, identity TEXT NOT NULL);
          CREATE TABLE requests (
            ordinal INTEGER PRIMARY KEY, invocation TEXT UNIQUE NOT NULL,
            request_key TEXT UNIQUE NOT NULL, owner TEXT NOT NULL, profile TEXT NOT NULL,
            endpoint TEXT NOT NULL, binding TEXT NOT NULL, body TEXT NOT NULL,
            response_id TEXT, response TEXT, rejected INTEGER NOT NULL DEFAULT 0,
            retired INTEGER NOT NULL DEFAULT 0);
          CREATE INDEX requests_owner ON requests(owner, ordinal);`);
      }
      if (metadata.create) db.prepare('INSERT INTO metadata VALUES (?, ?)').run(metadata.format, metadata.identity);
      db.exec('COMMIT');
      db.exec('PRAGMA journal_mode=WAL');
      return new WebRequestStore(db, metadata.identity);
    // DEFENSE: Schema/metadata admission or transaction failure during open must release the SQLite handle before propagating.
    } catch (error) { closeDatabase(db); throw error; }
  }

  constructor(db, identity) { this.db = db; this.identity = identity; }
  close() { this.db.close(); }
  latest(owner) {
    const records = this.db.prepare('SELECT * FROM requests WHERE owner=?').all(owner);
    return boundary('web.store_latest', { records, owner });
  }
  find(key) { return this.db.prepare('SELECT * FROM requests WHERE request_key=?').get(key); }

  prepare(request) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const record = this.db.prepare('SELECT * FROM requests WHERE invocation=?').get(request.invocation);
      const decision = boundary('web.store_prepare', { request, record: record ?? null,
        previous: this.latest(request.owner) ?? null, new_key: randomUUID() });
      // DEFENSE: A prepared invocation with unresolved remote work must retain its original key instead of creating another request.
      if (decision.action === 'retained') throw retainedRequest(decision.record);
      if (decision.action === 'reuse') {
        this.db.prepare('UPDATE requests SET rejected=0 WHERE request_key=?').run(decision.record.request_key);
      } else if (decision.action === 'insert') {
        const row = decision.record;
        this.db.prepare(`INSERT INTO requests (invocation, request_key, owner, profile, endpoint, binding, body)
          VALUES (?, ?, ?, ?, ?, ?, ?)`).run(row.invocation, row.request_key, row.owner, row.profile, row.endpoint, row.binding, row.body);
      }
      const selected = this.find(decision.record.request_key);
      this.db.exec('COMMIT');
      return selected;
    // DEFENSE: Receipt insertion/admission can fail within BEGIN IMMEDIATE; roll back before another invocation uses this connection.
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }

  identify(record, id) {
    const current = this.find(record.request_key);
    const decision = boundary('web.store_identify', { record, current, id });
    this.db.prepare('UPDATE requests SET response_id=?, rejected=? WHERE request_key=?')
      .run(decision.updates.response_id, decision.updates.rejected, record.request_key);
    Object.assign(record, decision.record);
  }

  finish(record, response) {
    const current = this.find(record.request_key);
    const decision = boundary('web.store_finish', { record, current, response });
    const write = decision.updates;
    this.db.prepare('UPDATE requests SET response_id=?, response=?, rejected=? WHERE request_key=?')
      .run(write.response_id, write.response, write.rejected, record.request_key);
    Object.assign(record, decision.record);
  }

  reject(record) {
    const { updates } = boundary('web.store_reject', { record });
    if (updates) this.db.prepare('UPDATE requests SET rejected=? WHERE request_key=?').run(updates.rejected, record.request_key);
  }

  retire(record) {
    const { updates } = boundary('web.store_retire', { record });
    this.db.prepare('UPDATE requests SET retired=? WHERE request_key=?').run(updates.retired, record.request_key);
  }
}
