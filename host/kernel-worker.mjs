import { parentPort, workerData } from 'node:worker_threads';
import { pathToFileURL } from 'node:url';
import { parseJson } from './codec.mjs';

const { default: model } = await import(pathToFileURL(workerData.module).href);
let world = model.initial();
parentPort.on('message', ({ frame: bytes, maximum }) => {
  try {
    // The native frame already defines the generic JSON token vocabulary.
    const frame = Buffer.from(bytes);
    const tokens = [];
    for (let offset = 4; offset < frame.length;) {
      const length = frame.readUInt32BE(offset);
      offset += 4;
      tokens.push(frame.subarray(offset, offset + length).toString('utf8'));
      offset += length;
    }
    let list = { $: 'Nil' };
    for (let index = tokens.length - 1; index >= 0; index--) list = { $: 'Con', head: tokens[index], tail: list };
    const output = model.packet(list, world);
    const shown = model.show(model.envelope(output));
    if (shown.$ !== 'Done') throw new Error(shown.error ?? 'Kernel envelope serialization failed');
    const text = shown.value;
    if (typeof text !== 'string' || Buffer.byteLength(text) > maximum) throw new Error('Kernel output exceeds its frame limit');
    const value = parseJson(text);
    if (typeof value.durable !== 'boolean' || typeof value.reply?.ok !== 'boolean' || !Array.isArray(value.effects)) {
      throw new Error('Malformed kernel decision');
    }
    world = model.state(output);
    parentPort.postMessage({ text, program: world });
  } catch (error) {
    parentPort.postMessage({ error: String(error?.message ?? error) });
  }
});
