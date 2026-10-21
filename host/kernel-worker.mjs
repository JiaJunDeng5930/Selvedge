import { parentPort, workerData } from 'node:worker_threads';
import { pathToFileURL } from 'node:url';

const model = await import(pathToFileURL(workerData.module).href);
let world = model.initial();
let projectedWorld;
let projection;
parentPort.on('message', ({ text: input, snapshot }) => {
  try {
    const output = model.packet(input, world);
    world = output.world;
    const text = output.envelope;
    if (snapshot) {
      // Extracted worlds are immutable; the same opaque handle has the same projection.
      if (world !== projectedWorld) {
        projection = model.observe(world);
        projectedWorld = world;
      }
      parentPort.postMessage({ text, programText: projection });
    } else parentPort.postMessage({ text });
  // DEFENSE: A failed extracted transition retires this worker; its uncommitted world must never serve another input.
  } catch (error) {
    parentPort.postMessage({ error: error.message });
  }
});
