import { parentPort, workerData } from 'node:worker_threads';
import { pathToFileURL } from 'node:url';

const model = await import(pathToFileURL(workerData.module).href);
let world = model.initial();
let projectedWorld;
let projection;
parentPort.on('message', ({ text: input, snapshot, operation, generation }) => {
  try {
    const output = operation === 'assess' ? model.assess(input, world) : model.packet(input, world);
    if (output.inputError) {
      parentPort.postMessage({ generation, inputError: output.inputError });
      return;
    }
    if (operation === 'assess') {
      parentPort.postMessage({ generation, text: output.envelope });
      return;
    }
    world = output.world;
    const text = output.envelope;
    if (snapshot) {
      // Extracted worlds are immutable; the same opaque handle has the same projection.
      if (world !== projectedWorld) {
        projection = model.observe(world);
        projectedWorld = world;
      }
      parentPort.postMessage({ generation, text, programText: projection });
    } else parentPort.postMessage({ generation, text });
  // DEFENSE: Extracted transitions can throw OCaml exception arrays; they must be failures even without a JavaScript message.
  } catch (error) {
    parentPort.postMessage({ generation, error: error instanceof Error ? error.message : String(error) });
  }
});
