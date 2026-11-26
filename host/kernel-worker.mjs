import { parentPort } from 'node:worker_threads';
import * as model from '../.build/kernel-model.mjs';

let world = model.initial();
let projectedWorld = world;
parentPort.on('message', ({ input, operation }) => {
  try {
    if (operation === 'loadState') {
      // DEFENSE: A different durable schema cannot be decoded as this world's records.
      if (input !== null && input.schema !== model.persistenceSchema) throw new Error('Unsupported Selvedge stored state schema');
      const restored = input === null ? model.initial() : model.restoreState(String(input.sequence), input.shared,
        input.tasks, input.titles, input.entities);
      // DEFENSE: A truncated or invalid stored record cannot initialize the Worker.
      if (restored === null) throw new Error('Invalid Selvedge stored state');
      world = projectedWorld = restored;
      parentPort.postMessage({
        programText: model.observe(world),
        ...(input === null ? { storage: { schema: model.persistenceSchema, shared: model.initialShared() } } : {}),
      });
      return;
    }
    const output = operation === 'assess' ? model.assess(input, world) : model.packet(input, world);
    if (output.inputError) {
      parentPort.postMessage({ inputError: output.inputError });
      return;
    }
    if (operation === 'assess') {
      parentPort.postMessage({ text: output.envelope });
      return;
    }
    world = output.world;
    const receipt = { text: output.envelope, reconcileRemote: output.reconcileRemote, storage: output.storage };
    // The journal already owns the projection of this immutable world handle.
    if (world === projectedWorld) parentPort.postMessage(receipt);
    else {
      parentPort.postMessage({ ...receipt, programUpdate: model.observePatch(projectedWorld, world, output.changedTasks) });
      projectedWorld = world;
    }
  // DEFENSE: Extracted transitions can throw OCaml exception arrays; they must be failures even without a JavaScript message.
  } catch (error) {
    parentPort.postMessage({ error: error instanceof Error ? error.message : String(error) });
  }
});
