import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { mkdir, open, lstat } from 'node:fs/promises';
import { existsSync, lstatSync } from 'node:fs';
import { isDeepStrictEqual } from 'node:util';
import path from 'node:path';
import { parseJson, stringifyJson } from './codec.mjs';

const format = 'selvedge-chatgpt-web-1';

export function retainedRequest(record) {
  const error = new Error(`ChatGPT Web request retained (${record.request_key}` +
    `${record.response_id ? `, response ${record.response_id}` : ''}); inspect or resume that request before continuing, or explicitly compact to start a new page`);
  error.name = 'ChatGPTWebRetainedRequest';
  error.requestKey = record.request_key;
  error.responseId = record.response_id;
  return error;
}

// This database records external request receipts, not task lifecycle. A native
// ticket authorizes creation; replay never calls this interpreter. Commit the
// original body/key before HTTP so an unknown outcome cannot acquire a new key.
export class WebRequestStore {
  static retireExisting(home, owner, ticket) {
    // Snapshot the target before yielding: a later task input must not cause
    // cancellation to retarget a newly admitted successor.
    const filename = path.join(home, 'providers', 'chatgpt-web', 'requests.sqlite');
    if (!existsSync(filename)) return null;
    if (!lstatSync(filename).isFile()) throw new Error('Invalid ChatGPT Web receipt database');
    const db = new DatabaseSync(filename);
    try {
      db.exec('PRAGMA busy_timeout=5000; PRAGMA synchronous=FULL; BEGIN IMMEDIATE');
      const record = ticket !== undefined ? db.prepare(`SELECT * FROM requests WHERE owner=? AND rejected=0
        AND invocation IN (?, ?) ORDER BY ordinal DESC LIMIT 1`).get(owner, `${owner}:${ticket}:0`, `${owner}:${ticket}:1`) :
        db.prepare('SELECT * FROM requests WHERE owner=? AND rejected=0 ORDER BY ordinal DESC LIMIT 1').get(owner);
      if (record) db.prepare('UPDATE requests SET retired=1 WHERE request_key=?').run(record.request_key);
      db.exec('COMMIT');
      return record;
    } finally { db.close(); }
  }

  static async open(home, { create = true } = {}) {
    const directory = path.join(home, 'providers', 'chatgpt-web');
    const filename = path.join(directory, 'requests.sqlite');
    if (create) await mkdir(directory, { recursive: true, mode: 0o700 });
    try {
      const info = await lstat(filename);
      if (!info.isFile() || info.isSymbolicLink()) throw new Error('Invalid ChatGPT Web receipt database');
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      if (!create) return null;
      const file = await open(filename, 'ax', 0o600).catch(error => {
        if (error.code !== 'EEXIST') throw error;
        return null;
      });
      await file?.close();
    }
    const db = new DatabaseSync(filename);
    try {
      db.exec(`PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;
        CREATE TABLE IF NOT EXISTS metadata (format TEXT NOT NULL, identity TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS requests (
          ordinal INTEGER PRIMARY KEY, invocation TEXT UNIQUE NOT NULL,
          request_key TEXT UNIQUE NOT NULL, owner TEXT NOT NULL, profile TEXT NOT NULL,
          endpoint TEXT NOT NULL, binding TEXT NOT NULL, body TEXT NOT NULL,
          response_id TEXT, response TEXT, rejected INTEGER NOT NULL DEFAULT 0,
          retired INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX IF NOT EXISTS requests_owner ON requests(owner, ordinal);`);
      db.exec('BEGIN IMMEDIATE');
      if (!db.prepare('SELECT 1 FROM metadata').get()) {
        db.prepare('INSERT INTO metadata VALUES (?, ?)').run(format, randomUUID());
      }
      const metadata = db.prepare('SELECT * FROM metadata').all();
      if (metadata.length !== 1 || metadata[0].format !== format) throw new Error('ChatGPT Web receipts are not in the current format');
      db.exec('COMMIT');
      return new WebRequestStore(db, metadata[0].identity);
    } catch (error) { db.close(); throw error; }
  }

  constructor(db, identity) { this.db = db; this.identity = identity; }
  close() { this.db.close(); }
  latest(owner) {
    return this.db.prepare('SELECT * FROM requests WHERE owner=? AND rejected=0 ORDER BY ordinal DESC LIMIT 1').get(owner);
  }
  find(key) { return this.db.prepare('SELECT * FROM requests WHERE request_key=?').get(key); }

  prepare({ invocation, owner, profile, endpoint, binding, body, reset = false }) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      let record = this.db.prepare('SELECT * FROM requests WHERE invocation=?').get(invocation);
      if (record) {
        if (record.retired) throw retainedRequest(record);
        if (record.owner !== owner || record.endpoint !== endpoint || record.binding !== binding ||
            !isDeepStrictEqual(parseJson(record.body), body)) {
          throw new Error('A committed ChatGPT Web request cannot change its body or connection');
        }
        this.db.prepare('UPDATE requests SET rejected=0 WHERE request_key=?').run(record.request_key);
      } else {
        const previous = this.latest(owner);
        // A receipt is explicit ownership, not a history-prefix heuristic. A
        // checkpoint is the native instruction to replace working context.
        if (previous && (body.previous_response_id ? previous.retired || previous.response_id !== body.previous_response_id || !previous.response : !reset)) {
          throw retainedRequest(previous);
        }
        const key = randomUUID();
        this.db.prepare(`INSERT INTO requests (invocation, request_key, owner, profile, endpoint, binding, body)
          VALUES (?, ?, ?, ?, ?, ?, ?)`).run(invocation, key, owner, profile, endpoint, binding, stringifyJson(body));
        record = this.find(key);
      }
      this.db.exec('COMMIT');
      return record;
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }

  identify(record, id) {
    if (typeof id !== 'string' || !id.length || id.length > 256 || /[\x00-\x20\x7f]/.test(id)) {
      throw new Error('ChatGPT Web returned an invalid response identity');
    }
    const current = this.find(record.request_key);
    if (current.response_id && current.response_id !== id) throw new Error('ChatGPT Web changed the response identity');
    this.db.prepare('UPDATE requests SET response_id=?, rejected=0 WHERE request_key=?').run(id, record.request_key);
    record.response_id = id;
  }

  finish(record, response) {
    this.identify(record, response.id);
    const encoded = stringifyJson(response);
    const current = this.find(record.request_key);
    if (current.response && !isDeepStrictEqual(parseJson(current.response), response)) {
      throw new Error('ChatGPT Web changed a committed response');
    }
    this.db.prepare('UPDATE requests SET response=?, rejected=0 WHERE request_key=?').run(encoded, record.request_key);
    record.response = encoded;
  }

  reject(record) {
    // Only an explicit pre-admission HTTP rejection permits another logical
    // request. Connection loss and interrupted resources remain uncertain.
    if (!record.response_id) this.db.prepare('UPDATE requests SET rejected=1 WHERE request_key=?').run(record.request_key);
  }

  retire(record) {
    // This is the receipt of an explicit cancellation intention, not evidence
    // that a remote server physically stopped. Only a later native effect may
    // authorize replacement work; unknown failures do not set this flag.
    this.db.prepare('UPDATE requests SET retired=1 WHERE request_key=?').run(record.request_key);
  }
}
