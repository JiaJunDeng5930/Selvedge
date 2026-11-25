import { dispatchControlResult } from './model-api.ts';
import { naturalKey } from './public/json-tokens.mjs';
import { boundary } from './public/model-boundary.mjs';

function include(index, owner, generation, row) {
  let bucket = index.get(owner);
  if (!bucket) {
    bucket = new Map();
    index.set(owner, bucket);
  }
  bucket.set(generation, row);
}

function exclude(index, owner, generation) {
  const bucket = index.get(owner);
  bucket.delete(generation);
  if (!bucket.size) index.delete(owner);
}

function newestFirst(entries) {
  return Array.from(entries, row => [BigInt(naturalKey(row.generation)), row])
    .sort(([left], [right]) => left > right ? -1 : left < right ? 1 : 0)
    .map(([, row]) => row);
}

// Dispatch needs coordinates and physical observations. The provider payload
// may contain a complete conversation or tool contract.
function controlObservation(observation) {
  if (!observation.effect) return observation;
  const { kind, task_id, ticket, operation_id, card_id, backend } = observation.effect;
  return { ...observation, effect: { kind, task_id, ticket, operation_id, card_id, backend } };
}

export class DispatchControl {
  #head = boundary('control.dispatch.initial', {});
  #generation = new Map();
  #task = new Map();
  #key = new Map();

  #select({ kind, value }) {
    switch (kind) {
      case 'none': return [];
      case 'generation': {
        const row = this.#generation.get(naturalKey(value));
        return row ? [row] : [];
      }
      case 'task': return newestFirst(this.#task.get(naturalKey(value))?.values() ?? []);
      case 'key': return newestFirst(this.#key.get(value)?.values() ?? []);
      case 'all': return newestFirst(this.#generation.values());
      // DEFENSE: An incompatible extracted host model cannot select a physical registry safely.
      default: throw new Error('Invalid dispatch scope');
    }
  }

  step(observed) {
    const observation = controlObservation(observed);
    const { running, ...coordinates } = observation;
    const active = this.#select(boundary('control.dispatch.select', { observation: coordinates }));
    const { state, ...actions } = dispatchControlResult(
      boundary('control.dispatch.step', { observation, state: { ...this.#head, active } }));
    const { active: updated, ...head } = state;
    for (const row of active) {
      const generation = naturalKey(row.generation);
      this.#generation.delete(generation);
      exclude(this.#key, row.key, generation);
      if (row.task !== null) exclude(this.#task, naturalKey(row.task), generation);
    }
    for (const row of updated) {
      const generation = naturalKey(row.generation);
      this.#generation.set(generation, row);
      include(this.#key, row.key, generation, row);
      if (row.task !== null) include(this.#task, naturalKey(row.task), generation, row);
    }
    this.#head = head;
    return actions;
  }
}
