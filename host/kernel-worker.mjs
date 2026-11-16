import { parentPort } from 'node:worker_threads';
import * as model from '../.build/kernel-model.mjs';

let world = model.initial();
let projectedWorld = world;
parentPort.on('message', ({ text: input, operation, replayVersion }) => {
  try {
    if (operation === 'observe') {
      parentPort.postMessage({ programText: model.observe(world) });
      projectedWorld = world;
      return;
    }
    if (operation === 'captureCheckpoint') {
      parentPort.postMessage({ checkpoint: { schema: model.checkpointSchema, data: model.checkpoint(world) } });
      return;
    }
    if (operation === 'restoreCheckpoint') {
      const restored = input.schema === model.checkpointSchema ? model.restoreCheckpoint(input.data) : null;
      if (restored !== null) world = restored;
      parentPort.postMessage(restored !== null);
      return;
    }
    const output = operation === 'replay' ? model.replay(replayVersion, input, world)
      : operation === 'assess' ? model.assess(input, world) : model.packet(input, world);
    if (output.inputError) {
      parentPort.postMessage({ inputError: output.inputError });
      return;
    }
    if (operation === 'assess') {
      parentPort.postMessage({ text: output.envelope });
      return;
    }
    world = output.world;
    if (operation === 'replay') {
      parentPort.postMessage(output.durable);
      return;
    }
    const receipt = { text: output.envelope, reconcileRemote: output.reconcileRemote };
    // The journal already owns the projection of this immutable world handle.
    if (world === projectedWorld) parentPort.postMessage(receipt);
    else {
      parentPort.postMessage({ ...receipt, programText: model.observe(world) });
      projectedWorld = world;
    }
  // DEFENSE: Extracted transitions can throw OCaml exception arrays; they must be failures even without a JavaScript message.
  } catch (error) {
    parentPort.postMessage({ error: error instanceof Error ? error.message : String(error) });
  }
});
