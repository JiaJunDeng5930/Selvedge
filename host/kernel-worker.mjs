import { parentPort, workerData } from 'node:worker_threads';
import { pathToFileURL } from 'node:url';

const { default: model } = await import(pathToFileURL(workerData.module).href);
let world = model.initial();
parentPort.on('message', ({ frame: bytes, snapshot }) => {
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
    const text = model.show(model.envelope(output));
    world = model.state(output);
    parentPort.postMessage(snapshot ? { text, program: world } : { text });
  // DEFENSE: Compiled JavaScript can fail at runtime, including the reproduced large-text stack overflow; the owner must reject the pending transition.
  } catch (error) {
    parentPort.postMessage({ error: error.message });
  }
});
