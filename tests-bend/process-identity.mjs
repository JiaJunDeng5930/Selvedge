import { readFile, readdir, readlink } from 'node:fs/promises';
import path from 'node:path';

const vanished = error => ['ENOENT', 'ESRCH', 'EACCES', 'EPERM'].includes(error.code);
const quote = value => `'${value.replaceAll("'", "'\\''")}'`;

export function longRunningCommand(filename) {
  const namespace = process.platform === 'linux'
    ? '"$(readlink /proc/self/ns/pid)"' : 'null';
  const format = process.platform === 'linux'
    ? '{"pid":%s,"namespace":"%s"}\\n' : '{"pid":%s,"namespace":%s}\\n';
  return `printf ${quote(format)} "$$" ${namespace} > ${quote(filename)}; exec sleep 60`;
}

export async function readHostPid(directory, filename) {
  let text;
  try { text = await readFile(path.join(directory, filename), 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return false; throw error; }
  // Opening the receipt precedes writing it. Wait for the complete single-line record.
  if (!text.endsWith('\n')) return false;
  const record = JSON.parse(text);
  if (!Number.isSafeInteger(record.pid) || record.pid <= 0 ||
      (process.platform === 'linux' ? !/^pid:\[\d+\]$/.test(record.namespace) : record.namespace !== null)) {
    throw new Error('Invalid process identity receipt');
  }
  if (process.platform !== 'linux') return record.pid;

  // /proc inside bwrap reports namespace-local IDs. Match both the namespace
  // inode and its local PID before using the host's process-liveness API.
  for (const entry of await readdir('/proc')) {
    if (!/^\d+$/.test(entry)) continue;
    try {
      const status = await readFile(`/proc/${entry}/status`, 'utf8');
      const ids = status.match(/^NSpid:\s*(.+)$/m)?.[1].trim().split(/\s+/);
      if (Number(ids?.at(-1)) !== record.pid) continue;
      if (await readlink(`/proc/${entry}/ns/pid`) === record.namespace) return Number(entry);
    } catch (error) { if (!vanished(error)) throw error; }
  }
  return false;
}
